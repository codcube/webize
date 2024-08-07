module Webize
  module HTML

    DOMnode = 'http://mw.logbook.am/webize/Node#' # node-schema base URI

    class Format < RDF::Format

      content_type 'text/html;q=0.8',
                   aliases: %w(application/xhtml+xml),
                   extensions: [:htm, :html, :xhtml]
      content_encoding 'utf-8'
      reader { Reader }
      writer { Writer }

    end

    class Reader < RDF::Reader

      format Format

      EmptyText = /\A[\n\t\s]+\Z/
      SRCSET = /\s*(\S+)\s+([^,]+),*/
      StripTags = /<\/?(br|em|font|hr|nobr|noscript|span|wbr)[^>]*>/i
      StyleAttr = /^on|border|color|style|theme/i

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @env = @base.respond_to?(:env) ? @base.env : HTTP.env
        @in = input.respond_to?(:read) ? input.read : input.to_s
        @options = options

        @isBookmarks = @in.index(BookmarkDoctype) == 0

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
        send(@isBookmarks ? :bookmarks : :scan_document){|s, p, o, graph = @base|
          fn.call RDF::Statement.new(s, Webize::URI.new(p), o,
                                     graph_name: graph)}
      end

      def read_RDFa? = false
      #def read_RDFa? = !@isBookmarks

      def scan_document &f

        @doc = Nokogiri::HTML.parse @in.gsub(StripTags, '')

        # resolve base URI
        if base = @doc.css('head base')[0]
          if baseHref = base['href']
            @base = HTTP::Node @base.join(baseHref), @env
            yield @env[:base], Contains, @base
          end
        end

        # strip upstream UI
        @doc.css('style').remove                                       # drop stylesheets
        @doc.traverse{|e|
          e.respond_to?(:attribute_nodes) && e.attribute_nodes.map{|a| # visit attributes
            attr = a.name                                              # attribute name
            a.unlink if attr.match? StyleAttr }}                       # drop attribute

        # <meta>
        @doc.css('meta').map{|m|
          if k = (m.attr('name') || m.attr('property'))  # predicate
            if v = (m.attr('content') || m.attr('href')) # object
              k = MetaMap[k] || k                        # map property-names
              case v
              when RelURI
                v = @base.join v
              when JSON::Outer
                v = JSON::Reader.new(v, base_uri: @base).scan_node &f
              end
              logger.warn ["no URI for META tag \e[7m", k, "\e[0m ", v].join unless k.to_s.match? /^(drop|http)/
              yield @base, k, v unless k == :drop
            end
          elsif m['http-equiv'] == 'refresh'
            if u = m['content'].split('url=')[-1]
              yield @base, Link, RDF::URI(u)
            end
          end

          m.remove}

        # <link>
        @doc.css('link[rel][href]').map{|m|

          # @href -> object
          v = HTTP::Node @base.join(m.attr 'href'), @env

          # @rel -> predicate
          m.attr('rel').split(/[\s,]+/).map{|k|
            @env[:links][:prev] ||= v if k.match? /prev(ious)?/i
            @env[:links][:next] ||= v if k.downcase == 'next'
            @env[:links][:icon] ||= v if k.match? /^(fav)?icon?$/i
            @env[:feeds].push v if k == 'alternate' && ((m['type']&.match?(/atom|feed|rss/)) || (v.path&.match?(/^\/feed\/?$/)))
            k = MetaMap[k] || k
            logger.warn ["no URI for LINK tag \e[7m", k, "\e[0m ", v].join unless k.to_s.match? /^(drop|http)/
            yield @base, k, v unless k == :drop || v.deny?}

          @env[:feeds].push v if Feed::Names.member?(v.basename) || Feed::Extensions.member?(v.extname)

          m.remove}

        # <title>
        @doc.css('title').map{|t|
          yield @base, Title, t.inner_text unless t.inner_text.empty?

          t.remove}

        # @doc.css('#next, #nextPage, a.next, .show-more > a').map{|nextPage|
        #   if ref = nextPage.attr('href')
        #     @env[:links][:next] ||= @base.join ref
        #   end}

        # @doc.css('#prev, #prevPage, a.prev').map{|prevPage|
        #   if ref = prevPage.attr('href')
        #     @env[:links][:prev] ||= @base.join ref
        #   end}

        # fix id-collisions to prevent unwanted cycles in tree/linked-list datastructures
        nodes = {}
        @doc.css('[id]').map{|node|    # identified node
          id = node['id']              # identifier
          if nodes[id]                 # repeated identifier?
            node.remove_attribute 'id' # turn into blank node
          else
            nodes[id] = true           # mark first occurrence
          end}

        # node scanner
        scan_node = -> node, depth = 0 {
          # subject identity
          subject = if node['id']   # identified node
                      RDF::URI '#' + CGI.escape(node.remove_attribute('id').value)
                    else
                      RDF::Node.new # blank node
                    end

          # type
          yield subject, Type, RDF::URI(DOMnode + node.name)

          # attributes
          node.attribute_nodes.map{|attr|

            p = attr.name
            o = attr.value

            case p
            when 'srcset'
              o.scan(SRCSET).map{|uri, _|
               yield subject, Image, @base.join(uri)}
            else # generic attribute emitter

              # apply attribute map and blocklist
              p = MetaMap[p] if MetaMap.has_key? p

              if p == :drop
               #puts ['drop:', subject, attr.name, o].join ' '
              else

                # unmapped predicate?
                unless p.match? HTTPURI
                  case p
                  when /^aria/i
                    p = 'https://www.w3.org/ns/aria#' + p.sub(/^aria[-_]/i,'')
                  when /type/i
                    p = Type
                  else
                    logger.warn ["no URI for DOM attr \e[7m", p, "\e[0m ", o[0..255]].join
                  end
                end

                case o
                when RelURI # URI string -> RDF::URI
                  o = Webize::Resource(@base.join(o), @env).relocate
                when JSON::Array
                  ::JSON.parse(o).map{|e|
                    yield subject, p, e if e}
                  o = nil
                when JSON::Outer # webize JSON in value field
                  o = JSON::Reader.new(o, base_uri: @base).scan_node &f rescue o
                end
                o = @base.join o if p == Link && o.class == String

                yield subject, p, o if o
              end
            end




          } if node.respond_to? :attribute_nodes

          # child nodes
          if depth > 30 || node.name == 'svg' # opaque HTML literal
            yield subject, Contains, RDF::Literal(node.to_html, datatype: RDF.HTML)
          else
            node.children.map{|child|
              if child.text? || child.cdata? # text literal
                if node.name == 'script'     # script node
                  if m = child.inner_text.match(JSON::Inner)
                    stringified = !m[1].nil? # serialized to string value?
                    text = m[2]              # raw JSON data
                    begin                    # read JSON
                      json = stringified ? (::JSON.load %Q("#{text}")) : text
                      json_node = JSON::Reader.new(json, base_uri: @base).scan_node &f
                      yield subject, Contains, json_node # emit JSON node
                    rescue
                      puts "SCRIPT #{child.inner_text[0..255]} " # parse failure
                    end
                  end
                else
                  case child.inner_text
                  when EmptyText
                  else
                    yield subject, Contains, child.inner_text.strip
                  end
                end
              else # child node
                yield subject, Contains, scan_node[child, depth + 1]
              end}
          end

          subject} # send node to caller for parent/child relationship triples

        yield @base, Contains, scan_node[@doc] # scan doc
      end
    end
  end
end
