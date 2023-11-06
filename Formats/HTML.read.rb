module Webize
  module HTML
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
          elsif !%w(a base).member?(m.name) # @href without @rel
            yield @base, Link, v
          end}

        # page pointers
        @doc.css('#next, #nextPage, a.next, .show-more > a').map{|nextPage|
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
              yield @base, Link, RDF::URI(u)
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

        @doc.css(MsgCSS[:post]).map{|post| # generate post identifier if missing
          post['id'] = 'post' + Digest::SHA2.hexdigest(rand.to_s) unless post['id']}

        # emit triples describing document fragment
        emitFragment = -> fragment {
          fragID = '#' + CGI.escape(fragment['id']) # fragment identifier

          # recursively visit DOM nodes in fragment, emit and reference identified subfragments as they're found
          walk = -> node {
            node.children.map{|n|
              unless n.text?
                if n['id'] # identified subfragment
                  yield fragID, Contains, (URI '#' + CGI.escape(n['id'])) # containment triple
                  emitFragment[n] unless DropNodes.member? n.name # emit fragment
                  n.remove
                else
                  walk[n]
                end
              end}}

          walk[fragment]

          # subject URI
          links = fragment.css MsgCSS[:permalink]
          subject = if links.empty?
                      fragID # fragment URI
                    else # inlined content from or about another base graph w/ URI permalink
                      if links.size > 1
                        links[1..-1].map{|link|
                          puts "@permalink: #{link}"
                          yield fragID, Link, @base.join(link['href'])}
                      end
                      graph = @base.join links[0]['href']
                      yield fragID, Contains, graph # better predicate? "exerpts" "transcludes" etc
                      puts "using #{graph} as identifier for inlined content"
                      graph
                    end

            # <img>
          fragment.css('img[src][alt], img[src][title]').map{|img|
            image = @base.join img['src']
            yield subject, Contains, image
            yield image, Type, RDF::URI(Image)
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
            if (title = subj.inner_text) && !title.empty?
              yield subject, Title, title
              subj.remove if title == subj.inner_html
            end}

          # sender
          (authorText = fragment.css(MsgCSS[:creator])).map{|c|
            yield subject, Creator, c.inner_text }
          (authorURI = fragment.css(MsgCSS[:creatorHref])).map{|c|
            yield subject, Creator, @base.join(c['href']) }
          [authorURI, authorText].map{|a|
            a.map{|c|
              c.remove }}

          # receiver
          fragment.css(MsgCSS[:reply]).map{|reply_of|
            yield subject, To, @base.join(reply_of['href'])
            reply_of.remove}

          # comment count
          #post.css('.comment-comments').map{|c|
          #if count = c.inner_text.strip.match(/^(\d+) comments$/)
          #yield subject, 'https://schema.org/commentCount', count[1]
                                            #end}

          # HTML content
          yield subject, Content,
                HTML.format(fragment, @base).send(%w(html head body div).member?(fragment.name) ? :inner_html : :to_html)}

        el = @doc.css('body')[0] || @doc # find <body> or entire document
        el['id'] = '' unless el['id']    # set default fragment identity
        emitFragment[el]                 # emit content

      end
    end
  end
end
