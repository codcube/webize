module Webize
  module HTML

    # markup-lambda tables

    # {type URI -> λ (resource, env) -> markup for resource of type }
    Markup = {}

    # {predicate URI -> λ (objects, env) -> markup for objects of predicate }
    MarkupPredicate = {}

    # templates for base RDF types

    MarkupPredicate['uri'] = -> us, env=nil {
      (us.class == Array ? us : [us]).map{|uri|
        {_: :a, c: :🔗,
         href: env ? Webize::Resource(uri, env).href : uri,
         id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}}

    MarkupPredicate[Type] = -> types, env {
      types.map{|t|
        t = Webize::Resource t, env
        {_: :a, class: :type, href: t.href,
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

    MarkupPredicate[Content] = MarkupPredicate[SIOC+'richContent'] = -> cs, env {cs.map{|c| markup c, env}}

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

    Markup[:kv] = -> kv, env {
      {_: :dl,
       c: kv.map{|k, vs|
         {c: ["\n",
              {_: :dt, c: MarkupPredicate[Type][[k], env]}, "\n",
              {_: :dd,
               c: MarkupPredicate.has_key?(k) ? MarkupPredicate[k][vs, env] : vs.map{|v|
                 markup(v, env)}}]}}}}

    Markup[Node + 'a'] = -> a, env {
      if links = a.delete(Link)
        ref = links[0]
        puts ["multiple link targets:", links].join ' ' if links.size > 1
      end
      {_: :a, c: [a.delete(Content),
                  ({_: :span, c: CGI.escapeHTML(ref.to_s.sub /^https?:..(www.)?/, '')} if ref),
                  Markup[:kv][a,env]]}.update(
        ref ? {href: ref,
               class: ref.host == env[:base].host ? 'local' : 'global'} : {})}

    Markup[Node + 'script'] = -> script, env {
      {class: :script,
       c: [{_: :span,
            style: 'font-size: 2em',
            c: :📜}]}}

    Markup[Schema + 'Document'] = -> graph, env {

      bc = String.new        # breadcrumb path

      host = env[:base].host # hostname

      bgcolor = if env[:deny]                # blocked?
                  if env[:base].deny_domain? # domain-block color
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

                 ({_: :title, c: CGI.escapeHTML(graph[env[:base].uri][Title].join ' ')} if graph.has_key?(env[:base].uri) &&
                                                                                           graph[env[:base].uri].has_key?(Title)),
                 {_: :style,
                  c: [CSS::Site,
                      "body {background-color: #{bgcolor}}",
                      "#updates {background: repeating-linear-gradient(#{rand(8) * 45}deg, #444, #444 1px, transparent 1px, transparent 16px)"].join("\n")},

                 env[:links].map{|type, resource|
                   {_: :link, rel: type, href: CGI.escapeHTML(Resource.new(resource).env(env).href)}}]},

            {_: :body,
             c: [({_: :img, class: :favicon,
                   src: env[:links][:icon].dataURI? ? env[:links][:icon].uri : env[:links][:icon].href} if env[:links].has_key? :icon),

                 {class: :toolbox,
                  c: [{_: :a, id: :rootpath, href: Resource.new(env[:base].join('/')).env(env).href, c: '&nbsp;' * 3}, "\n",  # 👉 root node
                      ({_: :a, id: :rehost, href: Webize::Resource(['//', ReHost[host], env[:base].path].join, env).href,
                        c: {_: :img, src: ['//', ReHost[host], '/favicon.ico'].join}} if ReHost.has_key? host),
                      {_: :a, id: :UI, href: host ? env[:base] : URI.qs(env[:qs].merge({'notransform'=>nil})), c: :🧪}, "\n", # 👉 origin UI
                      {_: :a, id: :cache, href: '/' + POSIX::Node(env[:base]).fsPath, c: :📦}, "\n",                          # 👉 cache location
                      ({_: :a, id: :block, href: '/block/' + host.sub(/^(www|xml)\./,''), class: :dimmed,                     # 👉 block domain
                        c: :🛑} if host && !env[:base].deny_domain?), "\n",
                      {_: :span, class: :path, c: env[:base].parts.map{|p|
                         bc += '/' + p                                                                                        # 👉 path breadcrumbs
                         ['/', {_: :a, id: 'p' + bc.gsub('/','_'), class: :path_crumb,
                                href: Resource.new(env[:base].join(bc)).env(env).href,
                                c: CGI.escapeHTML(Webize::URI(Rack::Utils.unescape p).basename || '')}]}}, "\n",
                      ([{_: :form, c: env[:qs].map{|k,v|                                                                      # searchbox
                           {_: :input, name: k, value: v}.update(k == 'q' ? {} : {type: :hidden})}},                          # preserve hidden search parameters
                        "\n"] if env[:qs].has_key? 'q'),
                      env[:feeds].uniq.map{|feed|                                                                             # 👉 feed(s)
                        feed = Resource.new(feed).env env
                        [{_: :a, href: feed.href, title: feed.path, c: FeedIcon, id: 'f' + Digest::SHA2.hexdigest(feed.uri)}. # 👉 feed
                           update((feed.path||'/').match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {}), "\n"]},
                      (:🔌 if env[:base].offline?),                                                                           # denote offline mode
                      {_: :span, class: :stats,
                       c: (elapsed = Time.now - env[:start_time] if env.has_key? :start_time                                  # ⏱️ elapsed time
                           [{_: :span, c: '%.1f' % elapsed}, :⏱️, "\n"] if elapsed > 1)}]},

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


    Markup[Schema + 'InteractionCounter'] = -> counter, env {
      if type = counter[Schema+'interactionType']
        type = type[0].to_s
        icon = Icons[type] || type
      end
      {_: :span, class: :interactionCount,
       c: [{_: :span, class: :type, c: icon},
           {_: :span, class: :count, c: counter[Schema+'userInteractionCount']}]}}

    Markup[BasicResource] = -> r, env {

      # predicate renderer lambda
      p = -> a {MarkupPredicate[a][r.delete(a),env] if r.has_key? a}

      if uri = r.delete('uri')                  # unless blank node:
        uri = Webize::Resource(uri, env)        # URI
        id = uri.local_id                       # fragment identity
        origin_ref = {_: :a, class: :pointer,   # origin pointer
                      href: uri, c: :🔗}
        ref = {_: :a, href: uri.href,           # pointer
                     id: 'p'+Digest::SHA2.hexdigest(rand.to_s)}
        color = if HostColor.has_key? uri.host  # host color
                  HostColor[uri.host]
                elsif uri.deny?
                  :red
                end
      end

      color = '#' + Digest::SHA2.hexdigest(     # dest color
                Webize::URI.new(r[To][0]).display_name)[0..5] if r.has_key?(To) &&
                                                                 r[To].size==1 &&
                                                                 [Webize::URI,Webize::Resource,RDF::URI].member?(r[To][0].class)
      {class: :resource,                         # resource
       c: [({class: :title, c: p[Title]}.        # title
              update(ref || {}) if r.has_key? Title),
           p[Abstract], p[To],                   # abstract, dest
           p[Content], p[SIOC+'richContent'],    # content
           (["\n", Markup[:kv][r,env],           # key/val fields
             "\n"] unless r.empty?),
           origin_ref,                           # origin pointer
          ]}.update(id ? {id: id} : {}).update(color ? {style: "background: repeating-linear-gradient(45deg, #{color}, #{color} 1px, transparent 1px, transparent 8px); border-color: #{color}"} : {})}

  end
end
