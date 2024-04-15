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

      DropAttrs = Webize.configList 'blocklist/attr'
      OpaqueNode = %w(svg)
      MaxDepth = 36
      StripTags = /<\/?(b|br|em|font|hr|nobr|noscript|span|wbr)[^>]*>/i

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @env = @base.respond_to?(:env) ? @base.env : HTTP.env
        @in = input.respond_to?(:read) ? input.read : input.to_s

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
        send(@isBookmarks ? :bookmarks : :scanContent){|s, p, o, g=nil|
          fn.call RDF::Statement.new(s, Webize::URI.new(p), o, graph_name: (Webize::URI.new g if g))}
      end

      def read_RDFa? = !@isBookmarks

      def scanContent &f

        @doc = Nokogiri::HTML.parse @in.gsub(StripTags, '')

        # resolve base URI
        if base = @doc.css('head base')[0]
          if baseHref = base['href']
            @base = HTTP::Node @base.join(baseHref), @env
          end
        end

        # strip upstream UI gunk
        @doc.css('style').remove
        @doc.traverse{|e|
          e.respond_to?(:attribute_nodes) && e.attribute_nodes.map{|a|  # inspect attributes
            attr = a.name                                               # attribute name
            a.unlink if DropAttrs.member?(attr) || attr.match?(/^on/i)} # drop attribute

        # <meta>
        @doc.css('meta').map{|m|
          if k = (m.attr('name') || m.attr('property'))  # predicate
            if v = (m.attr('content') || m.attr('href')) # object
              k = MetaMap[k] || k                        # map property-names
              v = @base.join v if v.match? /^(http|\/)\S+$/
              logger.warn ["no URI for <meta> attribute \e[7m", k, "\e[0m ", v].join unless k.to_s.match? /^(drop|http)/
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

          # href -> object
          v = HTTP::Node @base.join(m.attr 'href'), @env

          # rel -> predicate
          m.attr('rel').split(/[\s,]+/).map{|k|
            @env[:links][:prev] ||= v if k.match? /prev(ious)?/i
            @env[:links][:next] ||= v if k.downcase == 'next'
            @env[:links][:icon] ||= v if k.match? /^(fav)?icon?$/i
            @env[:feeds].push v if k == 'alternate' && ((m['type']&.match?(/atom|feed|rss/)) || (v.path&.match?(/^\/feed\/?$/)))
            k = MetaMap[k] || k
            logger.warn ["no URI for <link> attribute \e[7m", k, "\e[0m ", v].join unless k.to_s.match? /^(drop|http)/
            yield @base, k, v unless k == :drop || v.deny?}

          @env[:feeds].push v if Feed::Names.member?(v.basename) || Feed::Extensions.member?(v.extname)
          m.remove}

        # <title>
        @doc.css('title').map{|title|
          yield @base, Title, title.inner_text unless title.inner_text.empty?
          title.remove}

        @doc.css('head').remove

        # @doc.css('#next, #nextPage, a.next, .show-more > a').map{|nextPage|
        #   if ref = nextPage.attr('href')
        #     @env[:links][:next] ||= @base.join ref
        #   end}

        # @doc.css('#prev, #prevPage, a.prev').map{|prevPage|
        #   if ref = prevPage.attr('href')
        #     @env[:links][:prev] ||= @base.join ref
        #   end}

        #          origRef = Resource.new base.join e['href']              # resolve reference
#          ref = origRef.relocate                                  # optionally relocate reference
        #   blocked = ref.deny?
        #   offsite = ref.host != base.host
        #   if color = if HTML::HostColor.has_key? ref.host         # host-specific reference style
        #                HTML::HostColor[ref.host]
        #              elsif ref.scheme == 'mailto'
        #                '#48f'
        #              end
        #     e['class'] = 'host'
        #   elsif blocked
        #     e['class'] = 'blocked host'
        #   else
        #     e['class'] = offsite ? 'global' : 'local'             # local or global reference style

        # SrcSetRegex = /\s*(\S+)\s+([^,]+),*/
    #   srcset = node['srcset'].scan(SrcSetRegex).map{|url, size|
    #     [(base.join url), size].join ' '
    #   }.join(', ')
    #   srcset = base.join node['srcset'] if srcset.empty?

        #        @doc.css('script[type="application/json"], script[type="text/json"]').map{|json|
#          JSON::Reader.new(json.inner_text.strip.sub(/^<!--/,'').sub(/-->$/,''), base_uri: @base).scanContent &f}


        # remove duplicate IDs so we don't get cycles in tree/linked-list DSes. if we want addressibility we could mint a new ID but for now just turn into a blank node
        nodes = {}
        @doc.css('[id]').map{|node|
          id = node['id']
          if nodes[id]
            puts "duplicate node ID #{id}"
            node.remove_attribute 'id'
          else
            nodes[id] = true
          end}

        # recursive node reader. familiar DOM "next sibling" and "first child" properties are enough to reconstruct and preserve order in RDF
        scan_node = -> node, depth = 0 {

          # drop empty text content
          if node.text? && node.inner_text.match?(/^[\n\t\s]+$/)
            scan_node[node.next_sibling] if node.next_sibling
          else

            # identity
            subject = if node['id']
                        RDF::URI '#' + CGI.escape(node.remove_attribute('id').value)
                      else
                        RDF::Node.new # blank node
                      end

            # type
            name = node.name
            yield subject, Type, RDF::URI(Node)
            yield subject, Name, name

            # content
            yield subject, Content, node.inner_text if node.text?

            # attributes
            node.attribute_nodes.map{|attr|
              p = MetaMap[attr.name] || attr.name
              o = attr.value
              o = @base.join o if o.class == String && o.match?(/^(http|\/)\S+$/)
              logger.warn ["predicate URI unmapped for \e[7m", p, "\e[0m ", attr.value].join unless p.match? /^(drop|http)/
              yield subject, p, o unless p == :drop
            } if node.respond_to? :attribute_nodes

            if node.child

              if OpaqueNode.member?(name) || depth + node.children.size >= MaxDepth    # opaque[0] or in-too-deep[1] child nodes?
                yield subject, Content, RDF::Literal(node.to_html, datatype: RDF.HTML) # emit children as opaque HTML literal
              elsif child = scan_node[node.child, depth + 1]                           # emit first child as RDF node
                yield subject, Child, child
              end
            end

            # [0] so far the only opaque node is SVG. if you're reading a source doc for D3 or even more exoticly have
            # SVG that is simultaneously RDF/XML or RDFa you want to read as RDF, modify the OpaqueNodes constant above

            # [1] we haven't encountered depth issues in our reader on any of the gnarly stuff the web has for it to gnaw on,
            # but RDF writers hit stack limits with Ruby indirection/generics resulting in ~8 frames per node synergizing with the pathologically-deep autogenerated structures out there
            # you can bump up the stack size but who's gonna know you can do that or remember the env-var without looking it up? recursion wizards only

            # eventually we'll maybe come up with some fragment-caching strategy (or steal one from Intertwingler) or figure out tail-recursion tricks compatible with our datastructures and do away with the depth limits. or maybe just port everything to Haskell again

            if node.next_sibling
              if sibling = scan_node[node.next_sibling, depth + 1]                     # emit sibling as RDF node
                yield subject, Sibling, sibling
              end
            end

            subject                                                                    # emit node to caller for parent/child relationship triples
          end}

        yield @base, Type, RDF::URI(Node)
        yield @base, Child, scan_node[@doc]
      end
    end
  end
end
