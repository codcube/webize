module Webize
  module HTML

    DropNodes = %w(frame iframe link script style)
    QuotePrefix = /^\s*&gt;\s*/
    StripTags = /<\/?(noscript|wbr)[^>]*>/i

    def self.cachestamp html, baseURI              # input doc, base-URI
      doc = Nokogiri::HTML.parse html              # parse doc
      if head = doc.css('head')[0]                 # has head?
        base = head.css('base[href]')[0]           # find base node
        return html if base                        # nothing to do
      else                                         # headless?
        Console.logger.warn "⚠️ !head #{baseURI}"  # warn
        head = Nokogiri::XML::Node.new 'head', doc # create head
        if body = doc.css('body')[0]
          body.before head                         # attach head
        else
          doc.add_child head
        end
      end
      base = Nokogiri::XML::Node.new 'base', doc   # create base node
      base['href'] = baseURI                       # set base-URI
      head.add_child base                          # attach base node
      doc.to_html                                  # output doc
    end

    # (String -> String) or (Nokogiri -> Nokogiri)
    def self.format html, base

      # parse to Nokogiri document-fragment
      if html.class == String
        html = Nokogiri::HTML.fragment html.gsub(StripTags, '')
        serialize = true
      end

      html.css(DropNodes.join ', ').remove

      # <img> mapping
      html.css('[style*="background-image"]').map{|node|
        node['style'].match(CSS::URL).yield_self{|url|            # CSS background-image
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      html.css('amp-img').map{|amp|                               # amp-img
        amp.add_child "<img src=\"#{amp['src']}\">"}
      html.css("div[class*='image'][data-src]").map{|div|         # div[data-src]
        div.add_child "<img src=\"#{div['data-src']}\">"}
      html.css("figure[itemid]").map{|fig|                        # figure[itemid]
        fig.add_child "<img src=\"#{fig['itemid']}\">"}
      html.css("figure > a[href]").map{|a|                        # figure > a[href]
        a.add_child "<img src=\"#{a['href']}\">"}
      html.css("slide").map{|s|                                   # slide
        s.add_child "<img src=\"#{s['original']}\" alt=\"#{s['caption']}\">"}

      # <pre> formatting
      html.css('pre').map{|pre|
        pre.inner_html = pre.inner_html.lines.map{|l| wrapQuote l}.join}

      html.traverse{|e|
        e.respond_to?(:attribute_nodes) && e.attribute_nodes.map{|a| # inspect attributes
          attr = a.name                                           # attribute name
          e.set_attribute 'src',a.value if SRCnotSRC.member? attr # map alternative src attributes to @src
          e.set_attribute 'srcset',a.value if SRCSET.member? attr # map alternative srcset attributes to @srcset
          a.unlink if attr.match?(/^(aria|data|js|[Oo][Nn])|react/) ||
                      %w(autofocus bgcolor border color face height http-equiv id ping size style target width).member?(attr) ||
                      (attr == 'class' && !%w(greentext original q quote quote-text QuotedText).member?(a.value))} # drop attributes

        if e['src']
          src = URI.new base.join e['src']                        # resolve @src
          if src.deny?
            #Console.logger.debug "🚩 \e[31;1m#{src}\e[0m"
            e.remove
          else
            e['src'] = src.uri
          end
        end

        srcset e, base if e['srcset']                             # resolve @srcset

        if e['href']                                              # href attribute
          origRef = Resource.new base.join e['href']              # resolve reference
          ref = origRef.relocate                                  # optionally relocate reference
          ref.query = nil if ref.query&.match?(/utm[^a-z]/)       # deutmize query (tracker gunk)
          ref.fragment = nil if ref.fragment&.match?(/utm[^a-z]/) # deutmize fragment

          e['href'] = ref.to_s
          e['id'] = 'g' + Digest::SHA2.hexdigest(rand.to_s) if base.scheme == 'gemini'

          blocked = ref.deny?
          offsite = ref.host != base.host

          if color = if HTML::HostColor.has_key? ref.host         # host-specific reference style
                       HTML::HostColor[ref.host]
                     elsif ref.scheme == 'mailto'
                       '#48f'
                     end
            e['style'] = "border: 1px solid #{color}; color: #{color}"
            e['class'] = 'host'
          elsif blocked
            e['class'] = 'blocked host'
          else
            e['class'] = offsite ? 'global' : 'local'             # local or global reference style
          end

          e.inner_html = [
            if ref.imgURI? && e.css('img').empty?
              ['<img src="', ref.uri, '">']
            else
              case ref.scheme
              when 'data'
                :🧱
              when 'mailto'
                :📭
              when 'gemini'
                :🚀
              else
                if offsite && !blocked
                  ['<img src="//', ref.host, '/favicon.ico">']
                end
              end
            end,
            [origRef.to_s, # strip inner HTML if it's just the URL which we'll be displaying our way
             origRef.to_s.sub(/^https?:\/\//,'')].member?(e.inner_html) ? nil : e.inner_html,
            if ref.dataURI?                                       # inline data?
              ['<pre>',
               if ref.path.index('text/plain,') == 0              # show text content
                 CGI.escapeHTML(Rack::Utils.unescape ref.to_s[16..-1])
               else
                 ref.path.split(',',2)[0]                         # show content-type
               end,
               '</pre>'].join
            else                                                  # show identifier
              [' ', '<span class="id">',
               CGI.escapeHTML((if offsite
                               ref.uri.sub /^https?:..(www.)?/, ''
                              elsif ref.fragment
                                '#' + ref.fragment
                              else
                                [ref.path, ref.query ? ['?', ref.query] : nil].join
                               end)[0..127]),
               '</span>', ' ']
            end].join
        end}

      serialize ? html.to_html : html                             # serialize (string -> string) invocations
    end

    # resolve hrefs for current context
    def self.resolve_hrefs html, env, full=false
      return '' if !html || html.empty?                           # parse
      html = Nokogiri::HTML.send (full ? :parse : :fragment), (html.class==Array ? html.join : html)

      html.css('[src]').map{|i|                                   # @src
        i['src'] = Resource.new(env[:base].join(i['src'])).env(env).href}

      html.css('[srcset]').map{|i|                                # @srcset

        srcset = i['srcset'].scan(SrcSetRegex).map{|ref, size|
          [Webize::Resource(ref, env).href,
           size].join ' '
        }.join(', ')

        srcset = Webize::Resource(i['srcset'], env).href if srcset.empty?

        i['srcset'] = srcset}

      html.css('[href]').map{|a|
        a['href'] = Resource.new(env[:base].join(a['href'])).env(env).href} # @href

      html.to_html                                                # serialize
    end

    def self.wrapQuote line
      if m = (line.match QuotePrefix)
        if m.post_match.empty?
          nil
        else
          ['<span class="quote">',
           (wrapQuote m.post_match),
           '</span>'].join
        end
      else
        line
      end
    end

    class Document < Resource

      def grep graph
        qs = query_values || {}
        q = qs['Q'] || qs['q']
        return unless graph && q

        wordIndex = {}                                             # init word-index
        args = (q.shellsplit rescue q.split(/\W/)).map{|arg|arg.gsub RegexChars,''}.select{|arg| arg.size > 1}
        args.each_with_index{|arg,i|                               # populate word-index
          wordIndex[arg.downcase] = i }
        pattern = Regexp.new args.join('|'), Regexp::IGNORECASE    # query pattern

        graph.map{|uri, resource|                                  # visit resource
          if resource.to_s.match? pattern                          # matching resource?
            if resource.has_key? Content                           # resource has content?
              resource[Content].map!{|c|                           # visit content
                if c.class == RDF::Literal && c.datatype==RDF.HTML # HTML content?
                  html = Nokogiri::HTML.fragment c.to_s            # parse HTML
                  html.traverse{|n|                                # visit nodes
                    if n.text? && n.to_s.match?(pattern)           # matching text?
                      n.add_next_sibling n.to_s.gsub(pattern){|g|  # highlight match
                        HTML.render({_: :span, class: "w#{wordIndex[g.downcase]}", c: g})}
                      n.remove
                    end}
                  (c = RDF::Literal html.to_html).datatype = RDF.HTML
                end
                c}
            end
          else
            graph.delete uri unless host                           # drop local resources not in results
          end}

        css = RDF::Literal(HTML.render({_: :style,                 # highlighting CSS
                                        c: wordIndex.map{|word,i|
                                          ".post span.w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white} /* #{word} */\n"}}))
        css.datatype = RDF.HTML
        graph['#searchCSS'] = {Content => [css]}
      end
    end
  end
end
