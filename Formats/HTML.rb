# coding: utf-8
module Webize
  module CSS

    CodeCSS = Webize.configData 'style/code.css'
    SiteCSS = Webize.configData 'style/site.css'

  end
  module HTML
    include WebResource::URIs

    CSSURL = /url\(['"]*([^\)'"]+)['"]*\)/
    CSSgunk = /font-face|url/
    ReaderHosts = Webize.configList 'hosts/reader'
    NewsHosts = Webize.configList 'hosts/news'

    # (String -> String) or (Nokogiri -> Nokogiri)
    def self.format html, base

      # reader mode, less verbosity in output doc
      reader = ReaderHosts.member? base.host

      # parse string to nokogiri
      if html.class == String
        html = Nokogiri::HTML.fragment html.gsub(/<\/?(noscript|wbr)[^>]*>/i, '')
        serialize = true
      end

      # drop upstream formatting and scripts
      dropnodes = 'frame, iframe, script, style, link[rel="stylesheet"], link[type="text/javascript"], link[as="script"], a[href^="javascript"]'
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

      html.traverse{|e|
        e.respond_to?(:attribute_nodes) && e.attribute_nodes.map{|a| # inspect attributes
          attr = a.name                                           # attribute name
          e.set_attribute 'src',a.value if SRCnotSRC.member? attr # map alternative src attributes to @src
          e.set_attribute 'srcset',a.value if SRCSET.member? attr # map alternative srcset attributes to @srcset
          a.unlink if attr.match?(/^(aria|data|js|[Oo][Nn])|react/) ||
                      %w(bgcolor border color face height http-equiv ping size style target width).member?(attr) ||
                      (attr == 'class' && !%w(greentext q quote).member?(a.value))} # drop attributes

        if e['src']
          src = (base.join e['src']).R                            # resolve @src
          if src.deny?
            #Console.logger.debug "🚩 \e[31;1m#{src}\e[0m"
            e.remove
          else
            e['src'] = src.uri
          end
        end

        srcset e, base if e['srcset']                             # resolve @srcset

        if e['href']                                              # href attribute
          ref = (base.join e['href']).R                           # resolve @href
          ref.query = nil if ref.query&.match?(/utm[^a-z]/)       # deutmize query (tracker gunk)
          ref.fragment = nil if ref.fragment&.match?(/utm[^a-z]/) # deutmize fragment

          e['href'] = ref.to_s                                    # resolved href
          e['id'] = 'g' + Digest::SHA2.hexdigest(rand.to_s) if base.scheme == 'gemini'

          blocked = ref.deny?
          offsite = ref.host != base.host

          if color = if WebResource::HTML::HostColor.has_key? ref.host
                       WebResource::HTML::HostColor[ref.host]
                     elsif ref.scheme == 'mailto'
                       '#48f'
                     elsif blocked
                       'red'
                     end
            e['style'] = colorCSS = "#{offsite ? 'color: black; background-' : nil}color: #{color}" # host->color map
          end

          e.inner_html = [
            if reader
              nil
            elsif ref.imgURI? && e.css('img').empty?
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
            else                                                  # show URI
              ([' ', '<span', color ? [' style="', colorCSS, '"'] : nil, '>',
                CGI.escapeHTML((offsite ? ref.uri.sub(/^https?:..(www.)?/,'') : [ref.path, ref.query ? ['?', ref.query] : nil, ref.fragment ? ['#', ref.fragment] : nil].join)[0..127]),
                '</span>', ' '] unless reader)
            end].join

          css = []
          css.push offsite ? :global : :local                     # local or global styling
          css.push :blocked if blocked                            # blocked resource
          e['class'] = css.join ' '                               # add CSS classes

        elsif e['id'] && !reader                                  # identified node and verbose mode
          e.add_child " <span class='id'>##{e['id']}</span> "     # show identifier
        end}

      serialize ? html.to_html : html                             # serialize (string -> string) invocations
    end

    # resolve hrefs to proxy location
    def self.resolve_hrefs html, env, full=false
      return '' if !html || html.empty?                           # parse
      html = Nokogiri::HTML.send (full ? :parse : :fragment), (html.class==Array ? html.join : html)

      html.css('[src]').map{|i|                                   # @src
        i['src'] = env[:base].join(i['src']).R(env).href}

      html.css('[srcset]').map{|i|                                # @srcset
        srcset = i['srcset'].scan(SrcSetRegex).map{|ref, size|
          [ref.R(env).href, size].join ' '
        }.join(', ')
        srcset = i['srcset'].R(env).href if srcset.empty?
        i['srcset'] = srcset}

      html.css('[href]').map{|a|
        a['href'] = env[:base].join(a['href']).R(env).href} # @href

      html.to_html                                                # serialize
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
      include Console
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @env = @base.respond_to?(:env) ? @base.env : WebResource::HTTP.env
        @doc = Nokogiri::HTML.parse input.respond_to?(:read) ? input.read : input.to_s
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
          fn.call RDF::Statement.new(s.R, p.R,
                                     p == Content ? ((l = RDF::Literal o).datatype = RDF.HTML
                                                     l) : o,
                                     graph_name: g ? g.R : @base)}
      end

      def scanContent &f
        yield @base, Type, 'http://xmlns.com/foaf/0.1/Document'.R

        # resolve base URI
        if base = @doc.css('head base')[0]
          if baseHref = base['href']
            @base = @base.join(baseHref).R @env
          end
        end

        # site-reader
        @base.send Triplr[@base.host], @doc, &f if Triplr[@base.host]

        # @src
        @doc.css('[src]').map{|e|
          yield @base, Link, @base.join(e.attr('src')) unless %w(img style video).member? e.name}

        # @href
        @doc.css('[href]').map{|m|
          v = @base.join m.attr 'href' # @href object
          if rel = m.attr('rel')       # @rel predicate
            rel.split(/[\s,]+/).map{|k|
              @env[:links][:prev] ||= v if k.match? /prev(ious)?/i
              @env[:links][:next] ||= v if k.downcase == 'next'
              @env[:links][:icon] ||= v if k.match? /^(fav)?icon?$/i
              @env[:feeds].push v if k == 'alternate' && ((m['type']&.match?(/atom|rss/)) || (v.path&.match?(/^\/feed\/?$/))) && !@env[:feeds].member?(v)
              k = MetaMap[k] || k
              logger.warn ["predicate URI unmappped for \e[7m", k, "\e[0m ", v].join unless k.to_s.match? /^(drop|http)/
              yield @base, k, v unless k == :drop || v.R.deny?}
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
          yield @base, Title, title.inner_text }

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
          Webize::JSON::Reader.new(json.inner_text.strip.sub(/^<!--/,'').sub(/-->$/,''), base_uri: @base).scanContent &f}

        # <body>
        if body = @doc.css('body')[0]
          if NewsHosts.member? @base.host # only emit updates (host-wide, eliminates sidebars and boilerplate)
            hashed_nodes = 'article, aside, div, footer, h1, h2, h3, nav, p, section, b, span, ul, li'
            hashs = {}
            links = {}
            hashfile = ('//' + @base.host + '/.hashes').R
            linkfile = ('//' + @base.host + '/.links.u').R
            if linkfile.node.exist?
              site_links = {}
              linkfile.node.each_line{|l| site_links[l.chomp] = true}
              body.css('a[href]').map{|a|
                links[a['href']] = true
                a.remove if site_links.has_key?(a['href'])}
            else
              body.css('a[href]').map{|a|
                links[a['href']] = true}
            end
            if hashfile.node.exist?
              site_hash = {}
              hashfile.node.each_line{|l| site_hash[l.chomp] = true}
              body.css(hashed_nodes).map{|n|
                hash = Digest::SHA2.hexdigest n.to_s
                hashs[hash] = true
                n.remove if site_hash.has_key?(hash)}
            else
              body.css(hashed_nodes).map{|n|
                hash = Digest::SHA2.hexdigest n.to_s
                hashs[hash] = true}
            end
            hashfile.writeFile hashs.keys.join "\n" # update hashfile
            linkfile.writeFile links.keys.join "\n" # update linkfile
          end

                                                    # <body> content
          yield @base, Content, HTML.format(body, @base).inner_html
        else                                        # entire document
          yield @base, Content, HTML.format(@doc, @base).to_html
        end
      end
    end
  end
end

class WebResource
  module HTML

    FeedIcon = Webize.configData 'style/icons/feed.svg'
    HostColor = Webize.configHash 'style/color/host'
    Icons = Webize.configHash 'style/icons/map'
    SiteFont = Webize.configData 'style/fonts/hack.woff2'
    SiteIcon = Webize.configData 'style/icons/favicon.ico'
    StatusColor = Webize.configHash 'style/color/status'
    StatusColor.keys.map{|s|
      StatusColor[s.to_i] = StatusColor[s]}

    # Graph -> HTML
    def htmlDocument graph
      status = env[:origin_status]
      icon = join('/favicon.ico').R env                                                            # well-known icon location
      if env[:links][:icon]                                                                        # icon reference in metadata
        env[:links][:icon] = env[:links][:icon].R env unless env[:links][:icon].class==WebResource # normalize icon class
        if !env[:links][:icon].dataURI? &&                                                         # icon ref isn't data URI,
           env[:links][:icon].path != icon.path && env[:links][:icon] != self &&                   # isn't at well-known location, and
           !env[:links][:icon].node.directory? && !icon.node.exist? && !icon.node.symlink?         # target location is unlinked?
          icon.mkdir                                                                               # create container if needed
          FileUtils.ln_s (env[:links][:icon].node.relative_path_from icon.node.dirname), icon.node # link well-known location
        end
      end
      env[:links][:icon] ||= icon.node.exist? ? icon : '/favicon.ico'.R(env)                       # default icon
      bgcolor = if env[:deny]                                                                      # background color
                  if HostColor.has_key? host
                    HostColor[host]
                  elsif deny_domain?
                    '#f00'
                  else
                    '#f80'                                                                         # deny -> red
                  end
                elsif StatusColor.has_key? status
                  StatusColor[status]                                                              # status-code color
                elsif !host || offline?
                  '#000'                                                                           # offline or local -> black
                else
                  '#282828'                                                                        # online -> dark gray
                end
      css = "body {background: repeating-linear-gradient(-45deg, #000, #000 1em, #{bgcolor} 1em, #{bgcolor} 2em)}" # CSS

      htmlGrep graph                                                                               # grep results to markup

      link = -> key, content {                                                                     # lambda to render Link header
        if url = env[:links] && env[:links][key]
          [{_: :a, href: url.R(env).href, id: key, class: :icon, c: content},
           "\n"]
        end}

      HTML.render ["<!DOCTYPE html>\n",
                   {_: :html,
                    c: [{_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                            ({_: :title, c: CGI.escapeHTML(graph[uri][Title].join ' ')} if graph.has_key?(uri) && graph[uri].has_key?(Title)),
                             {_: :style, c: [Webize::CSS::SiteCSS, css]},
                             env[:links].map{|type, resource|
                               {_: :link, rel: type, href: CGI.escapeHTML(resource.R(env).href)}}]},
                        {_: :body,
                         c: [{_: :img, class: :favicon, src: env[:links][:icon].dataURI? ? env[:links][:icon].uri : env[:links][:icon].href},
                             uri_toolbar,
                             {class: :stats,
                              c: [({_: :span, c: env[:origin_status], class: :bold} if env[:origin_status] && env[:origin_status] != 200), # origin status
                                  (elapsed = Time.now - env[:start_time] if env.has_key? :start_time
                                   [{_: :span, c: '%.1f' % elapsed}, :⏱️] if elapsed > 1),                                         # elapsed time
                                  if env.has_key? :repository
                                    nGraphs = (env[:updates] || env[:repository]).graph_names.size
                                    nTriples = (env[:updates] || env[:repository]).size
                                    [([{_: :span, c: nGraphs}, :🗃] if nGraphs > 1),
                                     ([{_: :span, c: nTriples}, :⋮] if nTriples > 0)]
                                  end]},
                             (['<br>⚠️',{_: :span,class: :warning,c: CGI.escapeHTML(env[:warning])},'<br>'] if env.has_key? :warning), # warnings
                             link[:up,'&#9650;'],

                             HTML.group(graph.values, env).map{|group, resources|
                               group ||= ''
                               group = group.to_s if group.class == RDF::Literal # TODO cast to data: URI
                               nogroup = group == ''
                               group = group.R env
                               name = group.display_name
                               ch = nogroup ? '222222' : Digest::SHA2.hexdigest(name)[0..5]
                               color = ['#', ch].join
                               label = {_: :a,  href: group.href, style: "border-color: #{color}; color: #{color}",
                                        class: :label, c: CGI.escapeHTML(name)}

                               {class: :group,
                                c: [(label unless nogroup), '<br>',
                                    {class: :resources, style: "border-color: #{color}",
                                     c: case env[:view]
                                        when 'table'
                                          HTML.tabular resources, env
                                        else
                                          {style: "columns: auto 80ex; column-gap: 0",
                                           c: HTML.sort(resources, env).map{|v|
                                             HTML.markup v, env}}
                                        end}]}},

                             link[:prev,'&#9664;'], link[:down,'&#9660;'], link[:next,'&#9654;'],
                             {_: :script, c: Webize::Code::SiteJS}]}]}]
    end

    def htmlGrep graph
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
                                        ".w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white} /* #{word} */\n"}}))
      css.datatype = RDF.HTML
      graph['#searchCSS'] = {Content => [css]}
    end

    # RDF resource -> Markup
    def self.keyval t, env
      {_: :table, class: :kv,
       c: t.map{|k,vs|
         vs = (vs.class == Array ? vs : [vs]).compact
         {_: :tr,
          c: [{_: :td, class: 'k', c: MarkupPredicate[Type][[k], env]},
              {_: :td, class: 'v',
               c: MarkupPredicate.has_key?(k) ? MarkupPredicate[k][vs, env] : vs.map{|v|markup v, env}}]}}}
    end

    # Ruby value -> Markup
    def self.markup o, env
      case o
      when FalseClass                   # booleam
        {_: :input, type: :checkbox}
      when Hash                         # Hash
        return if o.empty?
        types = (o[Type]||[]).map{|t|Webize::MetaMap[t.to_s] || t.to_s} # map to rendered type
        seen = false
        [types.map{|type|               # typetag(s)
          if f = Markup[type]           # renderer defined for type
            seen = true                 # mark as shown
            f[o,env]                    # render as type
          end},
         (Markup['http://www.w3.org/2000/01/rdf-schema#Resource'][o, env] unless seen)]   # generic resource rendering
      when Integer
        o
      when RDF::Literal
        if [RDF.HTML, RDF.XMLLiteral].member? o.datatype
          if env[:proxy_href]           # rewrite hrefs
            Webize::HTML.resolve_hrefs o.to_s, env
          else
            o.to_s                      # HTML literal
          end
        else                            # String literal
          CGI.escapeHTML o.to_s
        end
      when RDF::URI                     # RDF::URI
        o = o.R env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when String                       # String
        CGI.escapeHTML o
      when Time                         # Time
        Markup[Date][o, env]
      when TrueClass                    # booleam
        {_: :input, type: :checkbox, checked: true}
      when WebResource                  # URI
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

  end
  include HTML
end
