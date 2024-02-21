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
      OpaqueNode = %w(svg)

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

        nodes = {}
        @doc.css('[id]').map{|node|
          id = node['id']
          if nodes[id]
            puts "duplicate node ID #{id}"
            node.remove_attribute 'id'
          else
            nodes[id] = true
          end
        }

        scan_node = -> node {

          # identified or 'blank' node
          subject = if node['id']
                      RDF::URI '#' + (CGI.escape node['id'])
                    else
                      RDF::Node.new
                    end

          print subject.class == RDF::URI ? subject : '.'

          name = node.name

          yield subject, Type, RDF::URI(DOMnode)

          if node.text?
            yield subject, Content, node.inner_text unless node.inner_text.match? /^[\n\t\s]+$/
          else
            yield subject, 'http://mw.logbook.am/webize#name', name unless name == 'div'
          end

          yield subject, Image, RDF::URI(node['src']) if name == 'img' && node['src']
          yield subject, Link, RDF::URI(node['href']) if name == 'a' && node['href']

          if node.child
            if OpaqueNode.member? name
              yield subject, Content, RDF::Literal(node.to_html, datatype: RDF.HTML)
            else
              yield subject, 'http://mw.logbook.am/webize#child', scan_node[node.child]
            end
          end

          yield subject, 'http://mw.logbook.am/webize#sibling', scan_node[node.next_sibling] if node.next_sibling

          subject}

        yield @base, Type, RDF::URI(DOMnode)
        yield @base, 'http://mw.logbook.am/webize#child', scan_node[@doc]
      end
    end
  end
end
