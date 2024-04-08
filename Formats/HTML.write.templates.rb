module Webize
  module HTML

    # markup-lambda tables

    # {type URI -> λ (resource, env) -> markup for resource of type }
    Markup = {}

    # {predicate URI -> λ (objects, env) -> markup for objects of predicate }
    MarkupPredicate = {}

    # templates for base types

    MarkupPredicate['uri'] = -> us, env=nil {
      (us.class == Array ? us : [us]).map{|uri|
        {_: :a, c: :🔗,
         href: env ? Webize::Resource(uri, env).href : uri,
         id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}}

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

    Markup[Schema + 'Document'] = -> graph, env {

      bgcolor = if env[:deny]                # blocked?
                  if HostColor.has_key? host # host color
                    HostColor[host]
                  elsif deny_domain?         # domain-block color
                    '#f00'
                  else                       # pattern-block color
                    '#f80'
                  end
                elsif StatusColor.has_key? env[:origin_status]
                  StatusColor[env[:origin_status]] # status color
                else
                  '#000'
                end

      link = -> key, content {               # lambda -> Link markup
        if url = env[:links] && env[:links][key]
          [{_: :a, href: Resource.new(url).env(env).href, id: key, class: :icon, c: content},
           "\n"]
        end}

      ["<!DOCTYPE html>\n",
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

                 Markup[Schema + 'DocumentToolbar'][graph, env],

                 (['<br>', {class: :warning, c: env[:warnings]}] unless env[:warnings].empty?), # warnings

                 ({class: :redirectors,
                   c: [:➡️, {_: :table,
                            c: HTTP::Redirector[env[:base]].map{|r|
                              {_: :tr,
                               c: [{_: :td, c: {_: :a, href: r.href, c: r.host}},
                                   {_: :td, c: ({_: :a, href: '/block/' + r.host.sub(/^(www|xml)\./,''), class: :dimmed, c: :🛑} unless r.deny_domain?)}]}}}]} if HTTP::Redirector[env[:base]]), # redirect sources

                 ({class: :referers,
                   c: [:👉, HTML.markup(HTTP::Referer[env[:base]], env)]} if HTTP::Referer[env[:base]]),       # referer sources

                 link[:up,'&#9650;'],                                                 # link to parent node

                 graph.values.map{|v| HTML.markup v, env },                           # graph data
#                (document[Contains].map{|v| HTML.markup v, env } if document.has_key? Contains), # child nodes

                 link[:prev,'&#9664;'], link[:down,'&#9660;'], link[:next,'&#9654;'], # link to previous, child, next node(s)

                 {_: :script, c: Code::SiteJS}]}]}]}

    Markup[Schema + 'DocumentToolbar'] = -> document, env {

      bc = '' # path breadcrumbs

      {class: :toolbox,
       c: [{_: :a, id: :rootpath, href: Resource.new(env[:base].join('/')).env(env).href, c: '&nbsp;' * 3}, "\n",  # 👉 root node
           ({_: :a, id: :rehost, href: Webize::Resource(['//', ReHost[host], env[:base].path].join, env).href,
             c: {_: :img, src: ['//', ReHost[host], '/favicon.ico'].join}} if ReHost.has_key? host),
           {_: :a, id: :UI, href: host ? env[:base] : URI.qs(env[:qs].merge({'notransform'=>nil})), c: :🧪}, "\n", # 👉 origin UI
           {_: :a, id: :cache, href: '/' + POSIX::Node(self).fsPath, c: :📦}, "\n",                                # 👉 archive
           ({_: :a, id: :block, href: '/block/' + host.sub(/^(www|xml)\./,''), class: :dimmed,                     # 👉 block domain
             c: :🛑} if host && !deny_domain?), "\n",
           {_: :span, class: :path, c: env[:base].parts.map{|p|
              bc += '/' + p                                                                                        # 👉 path breadcrumbs
              ['/', {_: :a, id: 'p' + bc.gsub('/','_'), class: :path_crumb,
                     href: Resource.new(env[:base].join(bc)).env(env).href,
                     c: CGI.escapeHTML(Webize::URI(Rack::Utils.unescape p).basename || '')}]}},
           "\n",
           ([{_: :form, c: env[:qs].map{|k,v|                                                                      # searchbox
                {_: :input, name: k, value: v}.update(k == 'q' ? {} : {type: :hidden})}},                          # preserve hidden search parameters
             "\n"] if env[:qs].has_key? 'q'),
           env[:feeds].uniq.map{|feed|                                                                             # 👉 feed(s)
             feed = Resource.new(feed).env env
             [{_: :a, href: feed.href, title: feed.path, c: FeedIcon, id: 'f' + Digest::SHA2.hexdigest(feed.uri)}. # 👉 feed
                update((feed.path||'/').match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {}), "\n"]},
           (:🔌 if offline?),                                                                                      # denote offline mode
           {_: :span, class: :stats,
            c: (elapsed = Time.now - env[:start_time] if env.has_key? :start_time                                  # ⏱️ elapsed time
                [{_: :span, c: '%.1f' % elapsed}, :⏱️, "\n"] if elapsed > 1)}]}}

    Markup[Schema + 'InteractionCounter'] = -> counter, env {
      if type = counter[Schema+'interactionType']
        type = type[0].to_s
        icon = Icons[type] || type
      end
      {_: :span, class: :interactionCount,
       c: [{_: :span, class: :type, c: icon},
           {_: :span, class: :count, c: counter[Schema+'userInteractionCount']}]}}

    # MIME.format_icon(MIME.fromSuffix link.extname)
    # (MarkupPredicate[Image][n[Image],env] if n.has_key? Image),

    # eventually we'll probably merge this with BasicResource, below
    Markup[Node] = -> n, env {

      name = n[Name].first if n.has_key? Name

      # consume typetag and cleanup empty field
      n[Type] -= [RDF::URI(Node)]
      n.delete Type if n[Type].empty?

      # attrs for key/val renderer
      rest = {}
      n.map{|k, v|
        rest[k] = v unless [Child, Sibling,
                            Content, Name].member? k}

      [{_: name || :div,
        class: :node,
        c: [if n.has_key? Content
            n[Content].map{|c| markup c, env }
           else
             {_: :span, class: :name, c: name} if name
            end,

            (HTML.keyval(rest, env) unless rest.empty?),

            # child node(s)
            (n[Child].map{|child|
               Markup[Node][child, env]} if n.has_key? Child)]},

       # sibling node(s)
       (n[Sibling].map{|sibling|
          Markup[Node][sibling, env]} if n.has_key? Sibling)]}

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
        rest[k] = re[k] unless [Abstract, Content, Creator, Date, From, SIOC + 'richContent', Title, 'uri', To, Type].member? k}

      env[:last] = re                                   # last resource pointer TODO group by title since that's all we're deduping run-to-run?

      {class: classes.join(' '),                        # resource
       c: [link,                                        # title
           p[Abstract],                                 # abstract
           to,                                          # destination
           from,                                        # source
           date,                                        # timestamp
           [Content, SIOC+'richContent'].map{|p|
             (re[p]||[]).map{|o|markup o,env}},         # body
           (HTML.keyval(rest, env) unless rest.empty?), # key/val view of remaining data
           origin_ref,                                  # origin pointer
          ]}.update(id ? {id: id} : {}).update(color ? {style: "background: repeating-linear-gradient(45deg, #{color}, #{color} 1px, transparent 1px, transparent 8px); border-color: #{color}"} : {})}

  end
end
