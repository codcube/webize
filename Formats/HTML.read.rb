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
          fn.call RDF::Statement.new(s, Webize::URI.new(p), o,
                                     graph_name: g ? Webize::URI.new(g) : @base) if s && p && o}
      end

      def scanContent &f

        # resolve base URI
        if base = @doc.css('head base')[0]
          if baseHref = base['href']
            @base = HTTP::Node @base.join(baseHref), @env
          end
        end

        # v = HTTP::Node @base.join(m.attr 'href'), @base.env # @href object
        # @env[:feeds].push v if Feed::Names.member?(v.basename) || Feed::Extensions.member?(v.extname)
        # if rel = m.attr('rel')       # @rel predicate
        #   rel.split(/[\s,]+/).map{|k|
        #     @env[:links][:prev] ||= v if k.match? /prev(ious)?/i
        #     @env[:links][:next] ||= v if k.downcase == 'next'
        #     @env[:links][:icon] ||= v if k.match? /^(fav)?icon?$/i
        #     @env[:feeds].push v if k == 'alternate' && ((m['type']&.match?(/atom|rss/)) || (v.path&.match?(/^\/feed\/?$/)))
        #     k = MetaMap[k] || k
        #     logger.warn ["predicate URI unmapped for \e[7m", k, "\e[0m ", v].join unless k.to_s.match? /^(drop|http)/
        #     yield @base, k, v unless k == :drop || v.deny?}            yield @base, Link, v
        # end


        # @doc.css('#next, #nextPage, a.next, .show-more > a').map{|nextPage|
        #   if ref = nextPage.attr('href')
        #     @env[:links][:next] ||= @base.join ref
        #   end}

        # @doc.css('#prev, #prevPage, a.prev').map{|prevPage|
        #   if ref = prevPage.attr('href')
        #     @env[:links][:prev] ||= @base.join ref
        #   end}

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

        # <title>
        @doc.css('title').map{|title|
          yield @base, Title, title.inner_text unless title.inner_text.empty?}

        # JSON
#        @doc.css('script[type="application/json"], script[type="text/json"]').map{|json|
#          JSON::Reader.new(json.inner_text.strip.sub(/^<!--/,'').sub(/-->$/,''), base_uri: @base).scanContent &f}
#              unless n.text?
        #                  yield fragID, Contains, (URI '#' + CGI.escape(n['id']))
          # <video>
          # ['video[src]', 'video > source[src]'].map{|vsel|
          #   fragment.css(vsel).map{|v|
          #     yield subject, Video, @base.join(v.attr('src')), graph}}


        scan_node = -> node {

          # identified or 'blank' DOM-node
          subject = if node['id']
                      RDF::URI '#' + (CGI.escape node['id'])
                    else
                      RDF::Node.new
                    end

          yield subject, Type, RDF::URI('#DOM_node')

          if node.text?
            yield subject, Content, node.inner_text
          else
            yield subject, Title, node.name
          end

          if child = node.child
            yield subject, '#child_node', scan_node[child]
          end

          if sibling = node.next_sibling
            yield subject, '#next_sibling', scan_node[sibling]
          end

          subject}

        yield @base, '#child_node', scan_node[@doc]
      end
    end
  end
end
