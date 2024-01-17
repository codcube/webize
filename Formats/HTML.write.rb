module Webize
  module HTML

    FeedIcon = Webize.configData 'style/icons/feed.svg'
    HostColor = Webize.configHash 'style/color/host'
    Icons = Webize.configHash 'style/icons/map'
    ReHost = Webize.configHash 'hosts/UI'
    SiteFont = Webize.configData 'style/fonts/hack.woff2'
    SiteIcon = Webize.configData 'style/icons/favicon.ico'
    StatusColor = Webize.configHash 'style/color/status'
    StatusColor.keys.map{|s|
      StatusColor[s.to_i] = StatusColor[s]}

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

    # value -> Markup
    def self.markup o, env
      case o
      when FalseClass         # booleam
        {_: :input, type: :checkbox}
      when Hash               # Hash
        return if o.empty?
        types = (o[Type]||[]).map{|t|
          MetaMap[t.to_s] || t.to_s} # map to renderable type
        seen = false
        [types.map{|type|     # type tag(s)
          if f = Markup[type] # renderer defined for type?
            seen = true       # mark as rendered
            f[o,env]          # render specific resource type
          end},               # render generic resource
         (Markup[BasicResource][o, env] unless seen)]
      when Integer
        o
      when RDF::Literal
        if [RDF.HTML, RDF.XMLLiteral].member? o.datatype
          if env[:proxy_refs] # proxy references
            resolve_hrefs o.to_s, env
          else
            o.to_s            # HTML literal
          end
        else                  # String literal
          CGI.escapeHTML o.to_s
        end
      when RDF::URI           # RDF::URI
        o = Resource.new(o).env env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when String             # String
        CGI.escapeHTML o
      when Time               # Time
        Markup[Date][o, env]
      when TrueClass          # booleam
        {_: :input, type: :checkbox, checked: true}
      when Webize::Resource   # Resource
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when Webize::URI        # URI
        o = Resource.new(o).env env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when Array              # Array
        o.map{|n| markup n, env}
      else                    # default
        puts "markup undefined for #{o.class}"
        {_: :span, c: CGI.escapeHTML(o.to_s)}
      end
    end

    # Markup -> HTML string
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

    class Document

      def write graph = {}
        bgcolor = if env[:deny]           # blocked
                    if HostColor.has_key? host       # host color
                      HostColor[host]
                    elsif deny_domain?    # domain block
                      '#f00'
                    else                  # pattern block
                      '#f80'
                    end
                  elsif StatusColor.has_key? env[:origin_status]
                    StatusColor[env[:origin_status]] # status color
                  else
                    '#000'
                  end

        grep graph                                   # markup grep results

        link = -> key, content {                     # lambda -> Link markup
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
                                    "body {background-color: #{bgcolor}}",
                                    "#updates {background: repeating-linear-gradient(#{rand(8) * 45}deg, #444, #444 1px, transparent 1px, transparent 16px)"].join("\n")},

                               env[:links].map{|type, resource|
                                 {_: :link, rel: type, href: CGI.escapeHTML(Resource.new(resource).env(env).href)}}]},

                          {_: :body,
                           c: [({_: :img, class: :favicon,
                                 src: env[:links][:icon].dataURI? ? env[:links][:icon].uri : env[:links][:icon].href} if env[:links].has_key? :icon),

                               toolbar,

                               (['<br>', {class: :warning, c: env[:warnings]}] unless env[:warnings].empty?), # warnings

                               ({c: [:➡️, HTML.markup(HTTP::Redirector[env[:base]], env)]} if HTTP::Redirector[env[:base]]), # redirect sources
                               ({c: [:👉, HTML.markup(HTTP::Referer[env[:base]], env)]} if HTTP::Referer[env[:base]]),       # referer sources

                               link[:up,'&#9650;'],

                               if updates = graph.delete('#updates') # updates
                                 HTML.markup updates, env
                               end,

                               if datasets = graph.delete('#datasets') # datasets
                                 HTML.markup datasets, env
                               end,

                               graph.values.map{|v| HTML.markup v, env }, # data

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
                       c: CGI.escapeHTML(Webize::URI(Rack::Utils.unescape p).basename || '')}]}},
             "\n",
             ([{_: :form, c: env[:qs].map{|k,v|                                                                      # searchbox
                  {_: :input, name: k, value: v}.update(k == 'q' ? {} : {type: :hidden})}},                          # invisible search parameters
               "\n"] if env[:qs].has_key? 'q'),
             env[:feeds].uniq.map{|feed|                                                                             # 👉 feed(s)
               feed = Resource.new(feed).env env
               [{_: :a, href: feed.href, title: feed.path, c: FeedIcon, id: 'f' + Digest::SHA2.hexdigest(feed.uri)}. # 👉 host feed
                 update((feed.path||'/').match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {}), "\n"]},
             (:🔌 if offline?),                                                                                      # denote offline mode
             {_: :span, class: :stats,
              c: (elapsed = Time.now - env[:start_time] if env.has_key? :start_time                                 # ⏱️ elapsed time
                  [{_: :span, c: '%.1f' % elapsed}, :⏱️, "\n"] if elapsed > 1)}
            ]}
      end

    end

    # markup-lambda tables

    # {type URI -> λ (resource, env) -> markup for resource of type }
    Markup = {}

    # {predicate URI -> λ (objects, env) -> markup for objects of predicate }
    MarkupPredicate = {}

    # markup lambdas for base types

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
        {_: :a, href: t.href,
         c: if t.uri == Contains
          nil
        elsif Icons.has_key? t.uri
          Icons[t.uri]
        else
          t.display_name
         end}}}

    MarkupPredicate[Abstract] = -> as, env {
      {class: :abstract, c: as.map{|a|[(markup a, env), ' ']}}}

    MarkupPredicate[Title] = -> ts, env {
      ts.map(&:to_s).map(&:strip).uniq.map{|t|
        [if t[0] == '#'
         {_: :span, class: :identifier, c: CGI.escapeHTML(t)}
        else
          CGI.escapeHTML t
         end, ' ']}}

    MarkupPredicate[Creator] = MarkupPredicate['http://xmlns.com/foaf/0.1/maker'] = -> creators, env {
      creators.map{|creator|
        if [Webize::URI, Webize::Resource, RDF::URI].member? creator.class
          uri = Webize::Resource.new(creator).env env
          name = uri.display_name
          color = Digest::SHA2.hexdigest(name)[0..5]
          {_: :a, class: :from, href: uri.href, style: "background-color: ##{color}", c: name}
        else
          markup creator, env
        end}}

    MarkupPredicate[To] = -> recipients, env {
      recipients.map{|r|
        if [Webize::URI, Webize::Resource, RDF::URI].member? r.class
          uri = Webize::Resource.new(r).env env
          name = uri.display_name
          color = Digest::SHA2.hexdigest(name)[0..5]
          {_: :a, class: :to, href: uri.href, style: "background-color: ##{color}", c: ['&rarr;', name].join}
        else
          markup r, env
        end}}

    Markup[Schema + 'InteractionCounter'] = -> counter, env {
      if type = counter[Schema+'interactionType']
        type = type[0].to_s
        icon = Icons[type] || type
      end
      {_: :span, class: :interactionCount,
       c: [{_: :span, class: :type, c: icon},
           {_: :span, class: :count, c: counter[Schema+'userInteractionCount']}]}}

    Markup[BasicResource] = -> re, env {
      env[:last] ||= {}                                 # previous resource

      types = (re[Type]||[]).map{|t|                    # RDF type(s)
        MetaMap[t.to_s] || t.to_s}

      classes = %w(resource)                            # CSS class(es)
      classes.push :post if types.member? Post

      p = -> a {                                        # predicate renderer
        MarkupPredicate[a][re[a],env] if re.has_key? a}

      titled = re.has_key?(Title) &&                    # has updated title?
               env[:last][Title]!=re[Title]

      if uri = re['uri']                                # unless blank node:
        uri = Webize::Resource.new(uri).env env         # full URI
        id = uri.local_id                               # fragment identifier
        origin_ref = {_: :a, class: :pointer,           # origin pointer
                      href: uri, c: :🔗}
        cache_ref = {_: :a, href: uri.href,             # cache pointer
                     id: 'p'+Digest::SHA2.hexdigest(rand.to_s)}
        color = if HostColor.has_key? uri.host          # color
                  HostColor[uri.host]
                elsif uri.deny?
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
      rest = {}                                         # remaining data
      re.map{|k,v|                                      # populate remaining attrs for key/val renderer
        rest[k] = re[k] unless [Abstract, Content, Creator, Date, From, Link, SIOC + 'richContent', Title, 'uri', To, Type].member? k}

      env[:last] = re                                   # last resource pointer TODO group by title since that's all we're deduping run-to-run?

      {class: classes.join(' '),                        # resource
       c: [link,                                        # title
           p[Abstract],                                 # abstract
           to,                                          # destination
           from,                                        # source
           date,                                        # timestamp
           [Content, SIOC+'richContent'].map{|p|
             (re[p]||[]).map{|o|markup o,env}},         # body
           p[Link],                                     # untyped links
           (HTML.keyval(rest, env) unless rest.empty?), # key/val view of remaining data
           origin_ref,                                  # origin pointer
          ]}.update(id ? {id: id} : {}).update(color ? {style: "background: repeating-linear-gradient(45deg, #{color}, #{color} 1px, transparent 1px, transparent 8px); border-color: #{color}"} : {})}

  end
end
