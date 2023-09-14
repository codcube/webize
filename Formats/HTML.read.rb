module Webize

  module CSS

    Code = Webize.configData 'style/code.css'
    Site = Webize.configData 'style/site.css'
    URL = /url\(['"]*([^\)'"]+)['"]*\)/

  end

  module HTML

    FeedIcon = Webize.configData 'style/icons/feed.svg'
    HostColor = Webize.configHash 'style/color/host'
    Icons = Webize.configHash 'style/icons/map'
    ReHost = Webize.configHash 'hosts/UI'
    SiteFont = Webize.configData 'style/fonts/hack.woff2'
    SiteIcon = Webize.configData 'style/icons/favicon.ico'
    StatusColor = Webize.configHash 'style/color/status'
    StatusColor.keys.map{|s|
      StatusColor[s.to_i] = StatusColor[s]}
    StripTags = /<\/?(noscript|wbr)[^>]*>/i
    QuotePrefix = /^\s*&gt;\s*/

    class Format < RDF::Format

      content_type 'text/html',
                   aliases: %w(application/xhtml+xml),
                   extensions: [:htm, :html, :xhtml]
      content_encoding 'utf-8'
      reader { Reader }

    end

    class Reader < RDF::Reader

      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @env = @base.respond_to?(:env) ? @base.env : HTTP.env
        @doc = Nokogiri::HTML.parse (input.respond_to?(:read) ? input.read : input.to_s).gsub(StripTags, '')

        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
        scanContent{|s,p,o,g=nil|
          o = Webize.date o if p.to_s == Date # normalize date formats
          fn.call RDF::Statement.new(Webize::URI.new(s),
                                     Webize::URI.new(p),
                                     p == Content ? ((l = RDF::Literal o).datatype = RDF.HTML
                                                     l) : o,
                                     graph_name: g ? Webize::URI.new(g) : @base) if s && p && o}
      end

      def scanContent &f

        # resolve base URI
        if base = @doc.css('head base')[0]
          if baseHref = base['href']
            @base = HTTP::Node @base.join(baseHref), @env
          end
        end

        # @src
        @doc.css('[src]').map{|e|
          yield @base, Link, @base.join(e.attr('src')) unless %w(img style video).member? e.name}

        # @href
        @doc.css('[href]').map{|m|
          v = HTTP::Node @base.join(m.attr 'href'), @base.env # @href object
          @env[:feeds].push v if Feed::Names.member?(v.basename) || Feed::Extensions.member?(v.extname)
          if rel = m.attr('rel')       # @rel predicate
            rel.split(/[\s,]+/).map{|k|
              @env[:links][:prev] ||= v if k.match? /prev(ious)?/i
              @env[:links][:next] ||= v if k.downcase == 'next'
              @env[:links][:icon] ||= v if k.match? /^(fav)?icon?$/i
              @env[:feeds].push v if k == 'alternate' && ((m['type']&.match?(/atom|rss/)) || (v.path&.match?(/^\/feed\/?$/)))
              k = MetaMap[k] || k
              logger.warn ["predicate URI unmapped for \e[7m", k, "\e[0m ", v].join unless k.to_s.match? /^(drop|http)/
              yield @base, k, v unless k == :drop || v.deny?}
          elsif !%w(a base).member?(m.name) # @href with no @rel
            yield @base, Link, v
          end}

        # page pointers
        @doc.css('#next, #nextPage, a.next').map{|nextPage|
          if ref = nextPage.attr('href')
            @env[:links][:next] ||= @base.join ref
          end}

        @doc.css('#prev, #prevPage, a.prev').map{|prevPage|
          if ref = prevPage.attr('href')
            @env[:links][:prev] ||= @base.join ref
          end}

        # <meta>
        @doc.css('meta').map{|m|
          if k = (m.attr('name') || m.attr('property'))  # predicate
            if v = (m.attr('content') || m.attr('href')) # object
              k = MetaMap[k] || k                        # map property-names
              case k
              when Abstract
                v = v.hrefs
              when /lytics/
                k = :drop
              else
                v = @base.join v if v.match? /^(http|\/)\S+$/
              end
              logger.warn ["no property URI for \e[7m", k, "\e[0m ", v].join unless k.to_s.match? /^(drop|http)/
              yield @base, k, v unless k == :drop
            end
          elsif m['http-equiv'] == 'refresh'
            if u = m['content'].split('url=')[-1]
              yield @base, Link, u.R
            end
          end}

        # <script>
        @doc.css('script').map{|s| # nonstandard src attrs used by lazy-loaders
          s.attribute_nodes.map{|a|
            unless %w(src type).member?(a.name) || !a.value.match?(/^(\/|http)/)
               logger.debug "<script> @#{a.name} #{a.value}"
              yield @base, Link, @base.join(a.value)
            end}}

        # <title>
        @doc.css('title').map{|title|
          yield @base, Title, title.inner_text unless title.inner_text.empty?}

        # JSON
        @doc.css('script[type="application/json"], script[type="text/json"]').map{|json|
          JSON::Reader.new(json.inner_text.strip.sub(/^<!--/,'').sub(/-->$/,''), base_uri: @base).scanContent &f}

        #         @doc.css(MsgCSS[:post]).map{|post|  # visit post(s) and add ID from :link or non-id addr if missing
        #           links = post.css(MsgCSS[:link])
        #                       post['data-post-no'] || post['id'] || post['itemid'] # identifier attribute

        # bind subject URI, traverse tree and emit triples describing content
        emitContent = -> subject, fragment {

          # traverse tree inside fragment boundary
          walkFragment = -> node {
            node.children.map{|n|
              if n.text?
                #n.remove if n.to_s.strip.empty?

                #if n.to_s.match?(/https?:\/\//) && n.parent.name != 'a'
                #n.add_next_sibling (CGI.unescapeHTML n.to_s).hrefs{|p,o| yield subject, p, o}
                #n.remove
                #end
              else
                if id = n['id']
                  id = '#' + id
                  yield subject, Contains, URI(id)
                  yield URI(id), Title, id
                  emitContent[id, n]
                  n.remove
                else
                  walkFragment[n]
                end
              end}}

          # traverse fragment
          walkFragment[fragment]

          # <img>
          fragment.css('img[src][alt], img[src][title]').map{|img|
            image = @base.join img['src']
            yield subject, Contains, image
            yield image, Type, Image.R
            %w(alt title).map{|attr|
              if val = img[attr]
                yield image, Abstract, val
              end}}

          # <video>
          ['video[src]', 'video > source[src]'].map{|vsel|
            fragment.css(vsel).map{|v|
              yield subject, Video, @base.join(v.attr('src'))}}

          # <datetime>
          fragment.css(MsgCSS[:date]).map{|d| # search on ISO8601 and UNIX timestamp selectors
            yield subject, Date, d[DateAttr.find{|a| d.has_attribute? a }] || d.inner_text
            d.remove}

          # title
          fragment.css(MsgCSS[:title]).map{|subj|
            puts subj
            if (title = subj.inner_text) && !title.empty?
              yield subject, Title, title
              subj.remove if title == subj.inner_html
            end}

          # creator
          (authorText = fragment.css(MsgCSS[:creator])).map{|c|
            yield subject, Creator, c.inner_text }
          (authorURI = fragment.css(MsgCSS[:creatorHref])).map{|c|
            yield subject, Creator, @base.join(c['href']) }
          [authorURI, authorText].map{|a|
            a.map{|c|
              c.remove }}

          # reply-of reference
          #c.css(MsgCSS[:reply]).map{|reply_of|
          #yield subject, To, @base.join(reply_of['href'])
          #reply_of.remove}

          # comment count
          #post.css('.comment-comments').map{|c|
          #if count = c.inner_text.strip.match(/^(\d+) comments$/)
          #yield subject, 'https://schema.org/commentCount', count[1]
                                            #end}

          # HTML content
          yield subject, Content, HTML.format(fragment, @base).to_html
        }

        # <html>
        emitContent[@base, @doc.css('body')[0]]

      end
    end
  end
end
