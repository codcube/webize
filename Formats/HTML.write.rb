module Webize
  module HTML

    def self.cachestamp html, baseURI              # input doc, base-URI
      doc = Nokogiri::HTML.parse html              # parse doc
      if head = doc.css('head')[0]                 # has head?
        base = head.css('base[href]')[0]           # find base node
        return html if base                        # nothing to do
      else                                         # headless?
        Console.logger.warn "⚠️ !head #{baseURI}"  # warn
        head = Nokogiri::XML::Node.new 'head', doc # create head
        doc.css('body')[0].before head             # attach head
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

      # drop upstream embeds, scripts, and styles
      dropnodes = 'frame, iframe, script, style, link[rel="stylesheet"], link[type="text/javascript"], link[as="script"], a[href^="javascript"]'
      #html.css(dropnodes).map{|n| Console.logger.debug "🚩 \e[31;1m#{n}\e[0m"}
      html.css(dropnodes).remove

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
                      %w(autofocus bgcolor border color face height http-equiv ping size style target width).member?(attr) ||
                      (attr == 'class' && !%w(greentext original q quote QuotedText).member?(a.value))} # drop attributes

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

    # RDF resource -> Markup
    def self.keyval t, env
      ["\n",
       {_: :table, class: :kv,
        c: t.map{|k,vs|
          vs = (vs.class == Array ? vs : [vs]).compact
          [{_: :tr,
            c: [{_: :td, class: 'k', c: MarkupPredicate[Type][[k], env]},
                {_: :td, class: 'v',
                 c: MarkupPredicate.has_key?(k) ? MarkupPredicate[k][vs, env] : vs.map{|v|markup v, env}}]}, "\n"]}}]
    end

    # Ruby value -> Markup
    def self.markup o, env
      case o
      when FalseClass                   # booleam
        {_: :input, type: :checkbox}
      when Hash                         # Hash
        return if o.empty?
        types = (o[Type]||[]).map{|t|MetaMap[t.to_s] || t.to_s} # map to rendered type
        seen = false
        [types.map{|type|               # typetag(s)
          if f = Markup[type]           # renderer defined for type
            seen = true                 # mark as shown
            f[o,env]                    # render as type
          end},
         (Markup[BasicResource][o, env] unless seen)] # show at least once
      when Integer
        o
      when RDF::Literal
        if [RDF.HTML, RDF.XMLLiteral].member? o.datatype
          if env[:proxy_href]           # rewrite hrefs
            resolve_hrefs o.to_s, env
          else
            o.to_s                      # HTML literal
          end
        else                            # String literal
          CGI.escapeHTML o.to_s
        end
      when RDF::URI                     # RDF::URI
        o = Resource.new(o).env env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when String                       # String
        CGI.escapeHTML o
      when Time                         # Time
        Markup[Date][o, env]
      when TrueClass                    # booleam
        {_: :input, type: :checkbox, checked: true}
      when Webize::Resource             # Resource
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when Webize::URI                  # URI
        o = Resource.new(o).env env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      else                              # renderer undefined
        {_: :span, c: CGI.escapeHTML(o.to_s)}
      end
    end

    # Markup -> String
    def self.render x
      case x
      when Array
        x.map{|n|render n}.join
      when Hash
        void = [:img, :input, :link, :meta].member? x[:_]
        '<' + (x[:_] || 'div').to_s +                        # open tag
          (x.keys - [:_,:c]).map{|a|                         # attr name
          ' ' + a.to_s + '=' + "'" + x[a].to_s.chars.map{|c| # attr value
            {"'"=>'%27', '>'=>'%3E', '<'=>'%3C'}[c]||c}.join + "'"}.join +
          (void ? '/' : '') + '>' + (render x[:c]) +         # child nodes
          (void ? '' : ('</'+(x[:_]||'div').to_s+'>'))       # close
      when NilClass
        ''
      when String
        x
      else
        CGI.escapeHTML x.to_s
      end
    end

    # resolve hrefs to current location
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

      def write graph = {}
        bgcolor = if env[:deny]                                                                      # background color
                    if HostColor.has_key? host
                      HostColor[host]
                    elsif deny_domain?
                      '#f00'
                    else
                      '#f80'                                                                         # deny -> red
                    end
                  elsif StatusColor.has_key? env[:origin_status]
                    StatusColor[env[:origin_status]]                                                 # status-code color
                  else
                    '#000'
                  end

        grep graph                                                                                   # markup grep results

        link = -> key, content {                                                                     # lambda -> Link header markup
          if url = env[:links] && env[:links][key]
            [{_: :a, href: Resource.new(url).env(env).href, id: key, class: :icon, c: content},
             "\n"]
          end}

        HTML.render ["<!DOCTYPE html>\n",
                     {_: :html,
                      c: [{_: :head,
                           c: [{_: :meta, charset: 'utf-8'},
                               ({_: :title, c: CGI.escapeHTML(graph[uri][Title].join ' ')} if graph.has_key?(uri) && graph[uri].has_key?(Title)),
                               {_: :style,
                                c: [CSS::Site,
                                    "body {background: repeating-linear-gradient(300deg, #{bgcolor}, #{bgcolor} 8em, #000 8em, #000 16em)}"].join("\n")},
                               env[:links].map{|type, resource|
                                 {_: :link, rel: type, href: CGI.escapeHTML(Resource.new(resource).env(env).href)}}]},
                          {_: :body,
                           c: [({_: :img, class: :favicon,
                                 src: env[:links][:icon].dataURI? ? env[:links][:icon].uri : env[:links][:icon].href} if env[:links].has_key? :icon),

                               toolbar,

                               ({class: :warning, c: env[:warning]} if env.has_key? :warning), # warning(s)

                               link[:up,'&#9650;'],

                               if updates = graph.delete('#updates') # updates at the top
                                 HTML.markup updates, env
                               end,

                               if datasets = graph.delete('#datasets') # datasets sidebar
                                 HTML.markup datasets, env
                               end,

                               graph.values.map{|v| HTML.markup v, env }, # graph data

                               link[:prev,'&#9664;'], link[:down,'&#9660;'], link[:next,'&#9654;'],

                               {_: :script, c: Code::SiteJS}]}]}]
      end

      def toolbar
        bc = '' # path breadcrumbs

        {class: :toolbox,
         c: [{_: :a, id: :rootpath, href: Resource.new(env[:base].join('/')).env(env).href, c: '&nbsp;' * 3}, "\n",  # 👉 root node
             ({_: :a, id: :rehost, href: Webize::Resource(['//', ReHost[host], env[:base].path].join, env).href,
               c: {_: :img, src: ['//', ReHost[host], '/favicon.ico'].join}} if ReHost.has_key? host),
             {_: :a, id: :UI, href: host ? env[:base] : URI.qs(env[:qs].merge({'notransform'=>nil})), c: :🧪}, "\n", # 👉 origin UI
             {_: :a, id: :cache, href: '/' + POSIX::Node(self).fsPath, c: :📦}, "\n",                                # 👉 archive
             ({_: :a, id: :block, href: '/block/' + host.sub(/^www\./,''), class: :dimmed,                           # 👉 block domain action
               c: :🛑} if host && !deny_domain?), "\n",
             {_: :span, class: :path, c: env[:base].parts.map{|p|
                bc += '/' + p                                                                                        # 👉 path breadcrumbs
                ['/', {_: :a, id: 'p' + bc.gsub('/','_'), class: :path_crumb,
                       href: Resource.new(env[:base].join(bc)).env(env).href,
                       c: CGI.escapeHTML(Rack::Utils.unescape p)}]}}, "\n",
             ([{_: :form, c: env[:qs].map{|k,v|                                                                      # searchbox
                  {_: :input, name: k, value: v}.update(k == 'q' ? {} : {type: :hidden})}},                          # invisible search parameters
               "\n"] if env[:qs].has_key? 'q'),
             env[:feeds].uniq.map{|feed|                                                                             # 👉 feed(s)
               feed = Resource.new(feed).env env
               [{_: :a, href: feed.href, title: feed.path, c: FeedIcon, id: 'f' + Digest::SHA2.hexdigest(feed.uri)}. # 👉 host feed
                 update((feed.path||'/').match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {}), "\n"]},
             (:🔌 if offline?),                                                                                      # denote offline mode
             {_: :span, class: :stats,
              c: [([{_: :span,class: :bold, c: env[:origin_status]},
                    "\n"] if env[:origin_status] && env[:origin_status] != 200),                                     # upstream status-code
                  (elapsed = Time.now - env[:start_time] if env.has_key? :start_time                                 # ⏱️ elapsed time
                   [{_: :span, c: '%.1f' % elapsed}, :⏱️, "\n"] if elapsed > 1)]}]}
      end

    end


    Markup = {}          # {URI -> lambda which emits markup for resource of type}
    MarkupPredicate = {} # {URI -> lambda which emits markup for objects of predicate}

    # markup generators for base attributes

    MarkupPredicate['uri'] = -> us, env=nil {
      (us.class == Array ? us : [us]).map{|uri|
        {_: :a, c: :🔗,
         href: env ? Webize::Resource(uri, env).href : uri,
         id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}}

    MarkupPredicate[Link] = -> links, env {
      tabular links.map{|link|
        link = Webize::URI link
        {'uri' => link.uri,
         Title => [MIME.format_icon(MIME.fromSuffix link.extname), link.host, link.basename]}}}

    MarkupPredicate[Type] = -> types, env {
      types.map{|t|
        t = Webize::Resource t, env
        {_: :a, href: t.href, c: Icons[t.uri] || t.display_name}.update(Icons[t.uri] ? {class: :icon} : {})}}

    MarkupPredicate[Abstract] = -> as, env {
      {class: :abstract, c: as.map{|a|[(markup a, env), ' ']}}}

    MarkupPredicate[Title] = -> ts, env {
      ts.map(&:to_s).map(&:strip).uniq.map{|t|
        [if t[0] == '#'
         {_: :span, class: :identifier, c: CGI.escapeHTML(t)}
        else
          CGI.escapeHTML t
         end, ' ']}}

    # generic resource renderer

    Markup[BasicResource] = -> re, env {
      env[:last] ||= {}

      classes = %w(resource)
      types = (re[Type]||[]).map{|t|MetaMap[t.to_s] || t.to_s} # map to rendered type
      classes.push :post if types.member? Post

      p = -> a {MarkupPredicate[a][re[a], env] if re.has_key? a}   # predicate renderer

      titled = (re.has_key? Title) && env[:last][Title]!=re[Title] # has title, changed from previous message?

      if uri = re['uri']                                           # unless blank node:
        uri = Webize::Resource.new(uri).env env; id = uri.local_id # full URI, fragment identifier
        origin_ref = {_: :a, class: :pointer, href: uri, c: :🔗}   # origin pointer
        cache_ref = {_: :a, href: uri.href, id: 'p'+Digest::SHA2.hexdigest(rand.to_s)} # cache pointer
        color = if HostColor.has_key? uri.host
                  HostColor[uri.host]
                elsif uri.deny?
                  env[:gradientR], env[:gradientA], env[:gradientB] = [300, 4, 8]
                  :red
                end
      end

      from = p[Creator]                                 # sender

      if re.has_key? To                                 # receiver
        if re[To].size == 1 && [Webize::URI, Webize::Resource, RDF::URI].member?(re[To][0].class)
          color = '#' + Digest::SHA2.hexdigest(Webize::URI.new(re[To][0]).display_name)[0..5]
        end
        to = p[To]
      end

      date = p[Date]                                    # date
      link = {class: :title, c: p[Title]}.              # title
               update(cache_ref || {}) if titled
      env[:last] = re                                   # update pointer to previous for next-render diff
      sz = rand(10) / 3.0                               # stripe size CSS

      rest = {}                                         # remaining data
      re.map{|k,v|                                      # populate remaining attrs for key/val renderer
        rest[k] = re[k] unless [Abstract, Content, Creator, Date, From, Link, SIOC + 'richContent', Title, 'uri', To, Type].member? k}

      {class: classes.join(' '),                        # resource
       c: [link,                                        # title
           p[Abstract],                                 # abstract
           date,                                        # timestamp
           from,                                        # source
           to,                                          # destination
           [Content, SIOC+'richContent'].map{|p|
             (re[p]||[]).map{|o|markup o,env}},         # body
           p[Link],                                     # untyped links
           (HTML.keyval(rest, env) unless rest.empty?), # key/val render of remaining data
           origin_ref,                                  # origin pointer
          ]}.update(id ? {id: id} : {}).update(color ? {style: "background: repeating-linear-gradient(#{env[:gradientR] ||= rand(360)}deg, #{color}, #{color} #{env[:gradientA] ||= rand(16) / 16.0}em, #000 #{env[:gradientA]}em, #000 #{env[:gradientB] ||= env[:gradientA] + rand(16) / 16.0}em); border-color: #{color}"} : {})}

  end
end
