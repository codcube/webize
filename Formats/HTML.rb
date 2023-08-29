# coding: utf-8
module Webize
  module CSS
    CodeCSS = Webize.configData 'style/code.css'
    SiteCSS = Webize.configData 'style/site.css'
  end
  module HTML
    CSSURL = /url\(['"]*([^\)'"]+)['"]*\)/
    CSSgunk = /font-face|url/
    FeedIcon = Webize.configData 'style/icons/feed.svg'
    HostColor = Webize.configHash 'style/color/host'
    Icons = Webize.configHash 'style/icons/map'
    ReHost = Webize.configHash 'hosts/UI'
    SiteFont = Webize.configData 'style/fonts/hack.woff2'
    SiteIcon = Webize.configData 'style/icons/favicon.ico'
    StatusColor = Webize.configHash 'style/color/status'
    StatusColor.keys.map{|s|
      StatusColor[s.to_i] = StatusColor[s]}

    # (String -> String) or (Nokogiri -> Nokogiri)
    def self.format html, base
      #print "FORMAT #{base} "

      # parse string to nokogiri
      if html.class == String
        html = Nokogiri::HTML.fragment html.gsub(/<\/?(noscript|wbr)[^>]*>/i, '')
        serialize = true
      end

      # drop upstream embeds, scripts, and styles
      dropnodes = 'frame, iframe, script, style, link[rel="stylesheet"], link[type="text/javascript"], link[as="script"], a[href^="javascript"]'
      #html.css(dropnodes).map{|n| Console.logger.debug "🚩 \e[31;1m#{n}\e[0m"}
      html.css(dropnodes).remove

      # <img> mapping
      html.css('[style*="background-image"]').map{|node|
        node['style'].match(CSSURL).yield_self{|url|              # CSS background-image -> img
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      html.css('amp-img').map{|amp|                               # amp-img -> img
        amp.add_child "<img src=\"#{amp['src']}\">"}
      html.css("div[class*='image'][data-src]").map{|div|         # div -> img
        div.add_child "<img src=\"#{div['data-src']}\">"}
      html.css("figure[itemid]").map{|fig|                        # figure -> img
        fig.add_child "<img src=\"#{fig['itemid']}\">"}
      html.css("figure > a[href]").map{|a|                        # figure -> img
        a.add_child "<img src=\"#{a['href']}\">"}
      html.css("slide").map{|s|                                   # slide -> img
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
          ref = URI.new base.join e['href']                       # resolve @href
          ref.query = nil if ref.query&.match?(/utm[^a-z]/)       # deutmize query (tracker gunk)
          ref.fragment = nil if ref.fragment&.match?(/utm[^a-z]/) # deutmize fragment

          e['href'] = ref.to_s                                    # resolved href
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
            e.inner_html == ref.uri ? nil : e.inner_html,
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
        elsif e['id']                                             # identified node?
          e.add_child " <span class='id'>##{e['id']}</span> "     # show identifier
        end}

      serialize ? html.to_html : html                             # serialize (string -> string) invocations
    end

    # resolve hrefs to proxy location
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

    QuotePrefix = /^\s*&gt;\s*/

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
                                c: [CSS::SiteCSS,
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
             env[:feeds].map{|feed|                                                                                  # 👉 feed(s)
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

    class Format < RDF::Format
      content_type 'text/html',
                   aliases: %w(application/xhtml+xml),
                   extensions: [:htm, :html, :xhtml]
      content_encoding 'utf-8'
      reader { Reader }
    end

    # HTML document -> RDF
    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @env = @base.respond_to?(:env) ? @base.env : HTTP.env
        @doc = Nokogiri::HTML.parse input.respond_to?(:read) ? input.read : input.to_s
        #puts "PARSE #{@base}"

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
        yield @base, Type, 'http://xmlns.com/foaf/0.1/Document'.R

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
          @env[:feeds].push v if Feed::Names.member? v.basename
          if rel = m.attr('rel')       # @rel predicate
            rel.split(/[\s,]+/).map{|k|
              @env[:links][:prev] ||= v if k.match? /prev(ious)?/i
              @env[:links][:next] ||= v if k.downcase == 'next'
              @env[:links][:icon] ||= v if k.match? /^(fav)?icon?$/i
              @env[:feeds].push v if k == 'alternate' && ((m['type']&.match?(/atom|rss/)) || (v.path&.match?(/^\/feed\/?$/))) && !@env[:feeds].member?(v)
              k = MetaMap[k] || k
              logger.warn ["predicate URI unmapped for \e[7m", k, "\e[0m ", v].join unless k.to_s.match? /^(drop|http)/
              yield @base, k, v unless k == :drop || v.deny?}
          elsif !%w(a base).member?(m.name) # @href with no @rel
            yield @base, Link, v
          end}

        # page pointers
        @doc.css('#next, #nextPage, a.next').map{|nextPage|
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
              yield @base, Link, u.R
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

        # <img>
        @doc.css('img[title], img[alt]').map{|img|
          if image = img['src']
            yield image, Type, Image.R
            %w(alt title).map{|attr|
              if val = img[attr]
                yield image, Abstract, val
              end}
          end}

        # <video>
        ['video[src]', 'video > source[src]'].map{|vsel|
          @doc.css(vsel).map{|v|
            yield @base, Video, @base.join(v.attr('src')) }}

        # inlined messages
        scanMessages &f

        # JSON
        @doc.css('script[type="application/json"], script[type="text/json"]').map{|json|
          JSON::Reader.new(json.inner_text.strip.sub(/^<!--/,'').sub(/-->$/,''), base_uri: @base).scanContent &f}

        # HTML content
        if body = @doc.css('body')[0]
          yield @base, Content, HTML.format(body, @base).inner_html # yield <body>
        else
          yield @base, Content, HTML.format(@doc, @base).to_html    # yield entire document
        end
      end
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

    # {URI -> render lambda}
    Markup = {}          # markup resource type
    MarkupPredicate = {} # markup objects of predicate

    MarkupPredicate['uri'] = -> us, env {
      (us.class == Array ? us : [us]).map{|uri|
        {_: :a, href: Webize::Resource(uri, env).href, c: :🔗, id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}}

  end
end
