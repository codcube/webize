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
        scanContent{|s, p, o, g=nil|
          fn.call RDF::Statement.new(s, Webize::URI.new(p), o, graph_name: (Webize::URI.new g if g))}
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

          # drop empty text nodes
          if node.text? && node.inner_text.match?(/^[\n\t\s]+$/)
            scan_node[node.next_sibling] if node.next_sibling
          else

            subject = if node['id']
                        RDF::URI '#' + (CGI.escape node['id'])
                      else
                        RDF::Node.new
                      end

            name = node.name

            yield subject, Type, RDF::URI(Node)

            if node.text?
              yield subject, Content, node.inner_text
            elsif name != 'div'
              yield subject, Name, name
            end

            node.attribute_nodes.map{|attr|
              puts [attr.name, attr.value].join ' '
            } if node.respond_to? :attribute_nodes

            if node.child
              if OpaqueNode.member? name
                yield subject, Content, RDF::Literal(node.to_html, datatype: RDF.HTML)
              elsif child = scan_node[node.child]
                yield subject, Child, child
              end
            end

            if node.next_sibling
              if sibling = scan_node[node.next_sibling]
                yield subject, Sibling, sibling
              end
            end

            subject
          end}

        yield @base, Type, RDF::URI(Node)
        yield @base, Child, scan_node[@doc]
      end
    end
  end
end
