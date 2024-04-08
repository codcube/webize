module Webize
  module HTML

    # this whole file is likely to go away once we replace calls to #format with 
    # the 'new' way of parse to RDF model of HTML doc, then serialize per our preference,
    # rather than parse to Nokogiri, do in-situ Nokogiri-facilitated massaging and output to RDF::HTML datatyped string

    # full HTML docs already use the new methods but sometimes we get HTML inside other stuff like RSS and JSON that ends up going through here

    DropAttrs = Webize.configList 'blocklist/attr'
    DropNodes = Webize.configList 'blocklist/node'
    DropPrefix = /^(aria|data|js|[Oo][Nn])|react/
    QuotePrefix = /^\s*&gt;\s*/
    StripTags = /<\/?(b|br|em|font|hr|nobr|noscript|span|wbr)[^>]*>/i

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

    ## rewrite doc to local format preferences
    # (String -> String)
    # (Nokogiri -> Nokogiri)
    def self.format html, base

      # parse to Nokogiri fragment
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
          attr = a.name                                              # attribute name
          e.set_attribute 'srcset', a.value if SRCSET.member? attr   # map alternative srcset attributes to @srcset
          a.unlink if DropAttrs.member?(attr) ||                     # drop attributes
                      attr.match?(DropPrefix) ||                     # drop prefixes            allow CSS classes
                      (attr == 'class' && !%w(greentext original q quote quote-text QuotedText).member?(a.value))}

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
  end
end
