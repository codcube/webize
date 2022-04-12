# coding: utf-8
module Webize
  module HTML
    include WebResource::URIs

    CSSURL = /url\(['"]*([^\)'"]+)['"]*\)/
    CSSgunk = /font-face|url/

    # clean HTML document
    def self.clean doc, base
      log = -> type, content, filter {               # logger
        print type + " \e[38;5;8m" + content.to_s.gsub(/[\n\r\s\t]+/,' ').gsub(filter, "\e[38;5;48m\\0\e[38;5;8m") + "\e[0m "}

      doc = Nokogiri::HTML.parse doc.gsub /<\/?(noscript|wbr)[^>]*>/i,'' # strip <noscript> <wbr>
      doc.traverse{|e|                               # visit nodes

        if e['src']                                  # src attribute
          src = (base.join e['src']).R               # resolve locator
          if src.deny?
            puts "🚩 \e[38;5;196m#{src}\e[0m" if Verbose
            e.remove                                 # strip gunk reference in src attribute
          end
        end

        if (e.name=='link' && e['href']) || e['xlink:href'] # href attribute
          ref = (base.join (e['href'] || e['xlink:href'])).R # resolve location
          if ref.deny? || %w(dns-prefetch preconnect).member?(e['rel'])
            puts "🚩 \e[38;5;196m#{ref}\e[0m" if Verbose
            e.remove                                 # strip gunk reference in href attribute
          end
        end}

      doc.css('meta[content]').map{|meta|            # strip gunk reference in meta tag
        if meta['content'].match? /^https?:/
          if meta['content'].R.deny?
            puts "🚩 #{meta['content']}" if Verbose
            meta.remove
          end
        end}

      doc.css('script').map{|s|                      # visit script-nodes
        s.attribute_nodes.map{|a|                    # @src and nonstandard attribute names
          if a.value.R.deny?                         # target denied?
            puts "🚩 \e[38;5;196m#{a.value}\e[0m" if Verbose
            s.remove                                 # strip gunk attribute
          end}}

      doc.css('style').map{|node|                    # strip CSS gunk
        Webize::CSS.cleanNode node if node.inner_text.match? CSSgunk}

      doc.css('[style]').map{|node|
        Webize::CSS.cleanAttr node if node['style'].match? CSSgunk}

      dropnodes = "amp-ad, amp-consent, .player-unavailable"
     #doc.css(dropnodes).map{|n| log['🧽', n, /amp-(ad|consent)/i]} if Verbose
      doc.css(dropnodes).remove                      # strip amp + popup gunk

      doc.css('[integrity]').map{|n|                 # content is being heavily modified,
        n.delete 'integrity'}                        # strip now-invalid integrity hash (TODO generate?)

      doc.to_html                                    # serialize clean(er) doc
    end

    # format HTML. (string -> string) or (nokogiri -> nokogiri)
    def self.format html, base

      # reader mode, less verbosity in output doc
      reader = base.env[:view] == 'reader' || ReaderHosts.member?(base.host)

      # parse string to nokogiri
      if html.class == String
        html = Nokogiri::HTML.fragment html
        serialize = true
      end

      # drop upstream formatting and scripts
      dropnodes = 'iframe, script, style, link[rel="stylesheet"], link[type="text/javascript"], link[as="script"]'  # a[href^="javascript"]
     #html.css(dropnodes).map{|n| puts ['🧽 ', n].join} if Verbose
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
                      (attr == 'class' && !%w(q quote).member?(a.value))}    # drop attribute

        if e['src']
          src = (base.join e['src']).R                            # resolve @src
          if src.deny?
            puts "🚩 \e[31;1m#{src}\e[0m" if Verbose
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
          blocked = ref.deny? && !LocalAllow.has_key?(ref.host)
          color = if HostColors.has_key? ref.host
                    HostColors[ref.host]
                  elsif blocked
                    'red'
                  end
          offsite = ref.host != base.host
          e['id'] = 'g' + Digest::SHA2.hexdigest(rand.to_s) if base.scheme == 'gemini'
          icon = case ref.scheme
                 when 'data'
                   :🧱
                 when 'mailto'
                   color = '#48f'
                   :📭
                 when 'gemini'
                   :🚀
                 else
                   if offsite && !blocked
                     ['<img src="//', ref.host, '/favicon.ico">']
                   end
                 end
          e.inner_html = [(icon unless reader),
                          e.inner_html == ref.uri ? nil : e.inner_html,
                          if ref.dataURI?                                                                               # inline data?
                            ['<pre>',
                             if ref.path.index('text/plain,') == 0                                                      # show text content
                               CGI.escapeHTML(Rack::Utils.unescape ref.to_s[16..-1])
                             else
                               ref.path.split(',',2)[0]                                                                 # show content-type
                             end,
                             '</pre>'].join
                          else                                                                                          # URI reference
                            ([' <span class=uri>', # show URI
                              CGI.escapeHTML((offsite ? ref.uri.sub(/^https?:..(www.)?/,'') : [ref.path, ref.query ? ['?', ref.query] : nil, ref.fragment ? ['#', ref.fragment] : nil].join)[0..127]),
                              '</span> '] unless reader)
                          end].join
          css = [:uri]
          css.push :path unless offsite                           # local or global reference class
          if blocked                                              # blocked-resource class
            css.push :blocked
          elsif color                                             # host->color map
            e['style'] = "#{offsite ? 'background-' : nil}color: #{color}"
          end
          e['href'] = ref.to_s                                    # resolved href
          e['class'] = css.join ' '                               # add CSS classes

        elsif e['id'] && !reader                                  # identified node w/o href attribute
          e.set_attribute 'class', 'identified'                   # style
          e.add_child " <span class='id'>#{e['id']}</span> "      # show identifier
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
        i['srcset'] = srcset unless srcset.empty?}

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
          if p.to_s == Date # normalize date formats
            o = o.to_s
            o = if o.match?(/^\d+$/) # unixtime
                  Time.at o.to_i
                elsif o.empty?
                  nil
                else
                  Time.parse o rescue puts("failed to parse time: #{o}")
                end
            o = o.utc.iso8601 if o
          end
          fn.call RDF::Statement.new(s.R, p.R,
                                     p == Content ? ((l = RDF::Literal o).datatype = RDF.HTML
                                                     l) : o,
                                     graph_name: g ? g.R : @base) if o
        }
      end

      def scanContent &f
        # document RDF type
        yield @base, Type, (FOAF+'Document').R

        # resolve inline base-URI declaration
        if base = @doc.css('head base')[0]
          if baseHref = base['href']
            @base = @base.join(baseHref).R @env
          end
        end

        # site-specific reader
        @base.send Triplr[@base.host], @doc, &f if Triplr[@base.host]


        # embedded frames
        @doc.css('frame, iframe').map{|frame|
          if src = frame.attr('src')
            src = @base.join(src).R
            unless src.deny?
              src = src.query_values['audio_file'].R if src.query && src.query_values.has_key?('audio_file')
              yield @base, Link, src
            end
          end}

        # typed references
        @doc.css('[rel][href]').map{|m|
          if rel = m.attr("rel") # predicate
            if v = m.attr("href") # object
              v = @base.join v
              rel.split(/[\s,]+/).map{|k|
                @env[:links][:prev] ||= v if k.match? /prev(ious)?/i
                @env[:links][:next] ||= v if k.downcase == 'next'
                @env[:links][:icon] ||= v if k.match? /^(fav)?icon?$/i
                @env[:feeds].push v if k == 'alternate' && ((m['type']&.match?(/atom|rss/)) || (v.path&.match?(/^\/feed\/?$/))) && !@env[:feeds].member?(v)
                k = MetaMap[k] || k
                puts [k, v].join "\t" unless k.to_s.match? /^(drop|http)/
                yield @base, k, v unless k == :drop || v.R.deny?}
            end
          end}

        # page pointers
        @doc.css('#next, #nextPage, a.next').map{|nextPage|
          if ref = nextPage.attr("href")
            @env[:links][:next] ||= @base.join ref
          end}

        @doc.css('#prev, #prevPage, a.prev').map{|prevPage|
          if ref = prevPage.attr("href")
            @env[:links][:prev] ||= @base.join ref
          end}

        # meta tags
        @doc.css('meta').map{|m|
          if k = (m.attr("name") || m.attr("property"))  # predicate
            if v = (m.attr("content") || m.attr("href")) # object
              k = MetaMap[k] || k                        # map property-names
              case k
              when Abstract
                v = v.hrefs
              when /lytics/
                k = :drop
              else
                v = @base.join v if v.match? /^(http|\/)\S+$/
              end
              puts [k,v].join "\t" unless k.to_s.match? /^(drop|http)/
              yield @base, k, v unless k == :drop
            end
          elsif m['http-equiv'] == 'refresh'
            yield @base, Link, m['content'].split('url=')[-1].R
          end}

        # title
        @doc.css('title').map{|title|
          yield @base, Title, title.inner_text }

        # images
        @doc.css('img[title], img[alt]').map{|img|
          if image = img['src']
            yield image, Type, Image.R
            %w(alt title).map{|attr|
              if val = img[attr]
                yield image, Abstract, val
              end}
          end}

        # videos
        ['video[src]', 'video > source[src]'].map{|vsel|
          @doc.css(vsel).map{|v|
            yield @base, Video, @base.join(v.attr('src')) }}

        # posts
        scanMessages &f

        # JSON
        @doc.css('script[type="application/json"], script[type="text/json"]').map{|json|
          Webize::JSON::Reader.new(json.inner_text.strip.sub(/^<!--/,'').sub(/-->$/,''), base_uri: @base).scanContent &f}

        # <body>
        if body = @doc.css('body')[0] # summarize to new content on origin refresh
          unless !@base.host || ReaderHosts.member?(@base.host) || @env[:fullContent] || @env[:origin_status] == 304 || @base.offline?
            @env[:links][:down] = WebResource::HTTP.qs @env[:qs].merge({'offline' => nil})
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

    # Graph -> HTML
    def htmlDocument graph
      status = env[:origin_status]
      elapsed = Time.now - env[:start_time] if env.has_key? :start_time
      icon = join('/favicon.ico').R env                                                            # well-known icon location
      if env[:links][:icon]                                                                        # icon reference in metadata
        env[:links][:icon] = env[:links][:icon].R env unless env[:links][:icon].class==WebResource # normalize iconref class
        if !env[:links][:icon].dataURI? &&                                                         # icon reference exists
           env[:links][:icon].path != icon.path && env[:links][:icon] != self &&                   # icon isn't at well-known location
           !env[:links][:icon].node.directory? && !icon.node.exist? && !icon.node.symlink?         # target location unlinked
          POSIX.container icon.fsPath                                                              # create container(s)
          FileUtils.ln_s (env[:links][:icon].node.relative_path_from icon.node.dirname), icon.node # link icon to well-known location
        end
      end
      env[:links][:icon] ||= icon.node.exist? ? icon : '/favicon.ico'.R(env)                       # default icon
      bgcolor = if env[:deny]                                                                      # background color
                  '#f00'                                                                           # deny -> red
                elsif HTTP::StatusColor.has_key? status
                  HTTP::StatusColor[status]                                                        # status-code map
                elsif !host || offline?
                  '#000'                                                                           # offline -> black
                else
                  '#333'                                                                           # online -> dark gray
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
                             {_: :style, c: [SiteCSS, css]},
                             env[:links].map{|type, resource|
                               {_: :link, rel: type, href: CGI.escapeHTML(resource.R(env).href)}}]},
                        {_: :body,
                         c: [{_: :img, id: :favicon, src: env[:links][:icon].dataURI? ? env[:links][:icon].uri : env[:links][:icon].href},
                             uri_toolbar,
                             ({_: :span, c: env[:origin_status], class: :bold} if env[:origin_status] && env[:origin_status] != 200), # origin status
                             ({_: :span, c: '%.1fs' % elapsed, class: :bold} if elapsed > 1),                                         # elapsed time
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
                             {_: :script, c: SiteJS}]}]}]
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
        types = (o[Type]||[]).map{|t|MetaMap[t.to_s] || t.to_s} # map to rendered type
        seen = false
        [types.map{|type|               # typetag(s)
          if f = Markup[type]           # renderer defined for type
            seen = true                 # mark as shown
            f[o,env]                    # render as type
          end},
         (Markup[Resource][o, env] unless seen)]   # generic resource rendering
      when Integer
        o
      when RDF::Literal
        if [RDF.HTML, RDF.XMLLiteral].member? o.datatype
          if env.has_key? :proxy_href   # rewrite hrefs
            Webize::HTML.resolve_hrefs o.to_s, env
          else
            o.to_s                      # HTML literal
          end
        else                            # String literal
          {_: :span, c: CGI.escapeHTML(o.to_s)}
        end
      when RDF::URI                     # RDF::URI
        o = o.R env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when String                       # String
        {_: :span, c: CGI.escapeHTML(o.to_s)}
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
