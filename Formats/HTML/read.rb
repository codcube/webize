module Webize
  module HTML
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
      OpaqueNode = %w(svg)
      SRCSET = /\s*(\S+)\s+([^,]+),*/
      StripTags = /<\/?(font|noscript)[^>]*>/i
      StyleAttr = /^on|border|color|dir|style|theme/i

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
        send(@isBookmarks ? :bookmarks : :scan_document){|s, p, o, graph|
          fn.call RDF::Statement.new(s, Webize::URI.new(p), o, graph_name: graph)}
      end

      # scan document fragment
      def scan_fragment &f
        scan_node Nokogiri::HTML.fragment(@in.gsub StripTags, ''), &f
      end

      # recursive DOM-node scanner
      def scan_node node, &f

        # subject identity
        subject = if node['id']   # identified node
                    RDF::URI '#' + CGI.escape(node.remove_attribute('id').value)
                  else
                    RDF::Node.new # blank node
                  end

        # type
        yield subject, Type, RDF::URI(XHV + node.name)

        # attributes
        node.attribute_nodes.map{|attr|

          # raw attributes
          p = attr.name
          o = attr.value

          # apply attribute map and blocklist
          p = MetaMap[p] if MetaMap.has_key? p

          next if p == :drop || o.empty? # attr not emitted as RDF

          # predicate

          unless p.match? HTTPURI
            case p
            when /^(data-)?aria/i
              p = 'https://www.w3.org/ns/aria#' + p.sub(/^(data-)?aria[-_]/i,'')
            when 'src'
              p = case node.name
                  when 'audio'
                    Audio
                  when 'iframe'
                    XHV + 'iframe'
                  when /ima?ge?/
                    Image
                  when 'video'
                    Video
                  else
                    puts "LINK #{node.name} #{o}"
                    Link
                  end
            when /type/i
              p = Type
            else
              logger.warn ["no URI for DOM attr \e[7m", p, "\e[0m ", o[0..255]].join
            end
          end

          # object
          href = -> {            # resolve reference in string value
            o = Webize::Resource(@base.join(o), @env).
                  relocate}

          case p                 # objects of specific predicate:
          when Audio
            href[]
          when Image
            href[]
          when Schema + 'srcSet' # parse @srcset
            o.scan(SRCSET).map{|uri, _|
              yield subject, Image, @base.join(uri), @base}
            next
          when Label             # tokenize @label
            o.split(/\s/).map{|label|
              yield subject, p, label, @base }
            next
          when Link              # @link untyped reference
            href[]
          when Video
            href[]
          else                   # objects of any predicate:
            case o
            when DataURI         # data URI
              o = Webize::Resource o, @env
            when RelURI          # resolve + relocate URI
              #puts "URI #{p} #{o}" # ideally we don't hit this and href-map on predicate instead of regex-sniffing
              href[]
            when JSON::Array     # JSON array
              o = JSON::Reader.new(o, base_uri: @base).scan_fragment &f rescue o
            when JSON::Outer     # JSON object
              o = JSON::Reader.new(o, base_uri: @base).scan_fragment &f rescue o
            end

          end

          # emit triples
          yield subject, p, o, @base # primary attr-mapped triple

          yield subject, Image, o, @base if p == Link && o.imgURI? # image triple

        } if node.respond_to? :attribute_nodes

        # child nodes
        if OpaqueNode.member?(node.name) # HTML literal
          yield subject, Contains, RDF::Literal(node.inner_html, datatype: RDF.HTML), @base
        elsif node.name == 'comment'
          yield subject, Contains, node.inner_text, @base
        else
          node.children.map{|child|
            if child.text? || child.cdata? # text literal
              if node.name == 'script'     # script node
                if m = child.inner_text.match(JSON::Inner) # content looks JSONish (TODO better detection, we optimistically feed a lot of stuff to the parser)
                  stringified = !m[1].nil? # serialized to string value?
                  text = m[2]              # raw JSON data
                  begin                    # read as JSON
                    json = stringified ? (::JSON.load %Q("#{text}")) : text
                    json_node = JSON::Reader.new(json, base_uri: @base).scan_fragment &f
                    yield subject, Contains, json_node, @base # emit JSON node
                  rescue
                    yield subject, Contains, child.inner_text.gsub(/\n/,'').gsub(/\s+/,' ')[0..255], @base
                  end
                else
                  yield subject, Contains, child.inner_text.gsub(/\n/,'').gsub(/\s+/,' ')[0..255], @base
                end
              else
                case child.inner_text
                when EmptyText
                else
                  yield subject, Contains, child.inner_text, @base
                end
              end
            else # child node
              yield subject, Contains, (scan_node child, &f), @base
            end}
        end

        subject # send node to caller for parent/child relationship triples
      end

      def scan_document &f

        @doc = Nokogiri::HTML.parse @in.gsub(StripTags, '')

        # resolve base URI
        if base = @doc.css('head base')[0]
          if baseHref = base['href']
            @base = HTTP::Node @base.join(baseHref), @env
          end
        end

        # strip upstream UI
        @doc.css('style').remove                                       # drop stylesheets

        @doc.traverse{|e|                                              # elements
          e.respond_to?(:attribute_nodes) && e.attribute_nodes.map{|a| # attributes
            attr = a.name                                              # attribute name
            a.unlink if attr.match? StyleAttr }}                       # drop style attributes

        @doc.css('script[src]').map{|s|                                # drop scripts
          yield @base, XHV + 'script', @base.join(s['src'])
          s.remove
        }

        # <meta>
        @doc.css('meta').map{|m|
          if k = (m.attr('itemprop') ||  # predicate
                  m.attr('name') ||
                  m.attr('property'))

            if o = (m.attr('content') || # object
                    m.attr('href'))

              p = MetaMap[k] || k        # map predicate

              case o                     # map object
              when RelURI
                o = @base.join o
              when JSON::Outer
                o = JSON::Reader.new(o, base_uri: @base).scan_fragment &f
              end

              logger.warn ["META no URI \e[7m", p, "\e[0m ", o].join unless p.to_s.match? /^(drop|http)/

              yield @base, p, o, @base unless p == :drop
              m.remove
            end
          elsif eq = m['http-equiv']
            case eq
            when 'refresh'
              if u = m['content'].split('url=')[-1]
                yield @base, Link, RDF::URI(u), @base
              end
            else
              #puts "HTTP-EQUIV #{eq}"
            end
            m.remove
          else
            #puts "META #{m}"
          end}

        # <link>
        @doc.css('link[rel][href]').map{|m|

          # @href -> object
          o = HTTP::Node @base.join(m.attr 'href'), @env

          # @rel -> predicate
          m.attr('rel').split(/[\s,]+/).map{|k|
            @env[:links][:prev] ||= o if k.match? /prev(ious)?/i
            @env[:links][:next] ||= o if k.downcase == 'next'
            @env[:links][:icon] ||= o if k.match? /^(fav)?icon?$/i
            @env[:feeds].push o if k == 'alternate' && ((m['type']&.match?(/atom|feed|rss/)) || (o.path&.match?(/^\/feed\/?$/)))
            p = MetaMap[k] || k
            logger.warn ["no URI for LINK tag \e[7m", k, "\e[0m ", o].join unless p.to_s.match? /^(drop|http)/
            if p == :drop
              puts "\e[38;5;196m-<link>\e[0m #{k} #{o}"
            else
              yield @base, p, o, @base
              m.remove
            end
          }

          @env[:feeds].push o if Feed::Names.member?(o.basename) || Feed::Extensions.member?(o.extname)}

        # <title>
        @doc.css('title').map{|t|
          yield @base, Title, t.inner_text, @base unless t.inner_text.empty?}

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

        yield @base, Contains, (scan_node @doc, &f), @base # scan document
      end
    end
  end
end
