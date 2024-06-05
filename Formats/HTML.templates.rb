module Webize
  module HTML
    class Property
 
      # predicate URI -> markup method
      Markup = {
        'uri' => :identifier,
        Type => :rdf_type,
        Abstract => :abstract,
        Title => :title,
        Creator => :creator,
        To => :to,
      }

      # type-specific property-markup methods

      def abstract as
        {class: :abstract,
         c: as.map{|a| [(markup a, env), ' ']}}
      end

      def creator creators
        creators.map{|creator|
          if Resources.member? creator.class
            uri = Webize::Resource.new(creator).env env
            name = uri.display_name
            color = Digest::SHA2.hexdigest(name)[0..5]
            {_: :a, class: :from, href: uri.href, style: "background-color: ##{color}", c: name}
          else
            markup creator, env
          end}
      end

      def identifier uris
        (uris.class == Array ? uris : [uris]).map{|uri|
          {_: :a, c: :🔗,
           href: env ? Webize::Resource(uri, env).href : uri,
           id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}
      end

      def property p,o
        Property.new(p).env(env).markup o
      end

      def rdf_type types
        types.map{|t|
          t = Webize::Resource t, env
          {_: :a, class: :type, href: t.href,
           c: if t.uri == Contains
            nil
          elsif Icons.has_key? t.uri
            Icons[t.uri]
          else
            t.display_name
           end}}
      end

      def title ts
        ts.map(&:to_s).map(&:strip).uniq.map{|t|
          [if t[0] == '#'
           {_: :span, class: :identifier, c: CGI.escapeHTML(t)}
          else
            CGI.escapeHTML t
           end, ' ']}
      end

      def to recipients
        recipients.map{|r|
          if Resources.member? r.class
            uri = Webize::Resource.new(r).env env
            name = uri.display_name
            color = Digest::SHA2.hexdigest(name)[0..5]
            {_: :a, class: :to, href: uri.href, style: "background-color: ##{color}", c: ['&rarr;', name].join}
          else
            markup r, env
          end}
      end
    end

    class Node

      # type URI -> markup method
      Markup = {
        DOMnode + 'a' => :anchor,
        DOMnode + 'script' => :script,
        Schema + 'Document' => :document,
        Schema + 'InteractionCounter' => :interactions}

      %w(div p ul ol li).map{|e| # DOM node types
        Markup[e] = :element}

      # type-specific resource-markup methods

      def keyval kv
        {_: :dl,
         c: kv.map{|k, vs|
           {c: ["\n",
                {_: :dt, c: property(Type,[k])}, "\n",
                {_: :dd,
                 c: Property::Markup.has_key?(k) ? property(k,vs) : vs.map{|v|
                   markup(v, env)}}]}}}
      end

      def anchor a
        if links = a.delete(Link)
          ref = links[0]
          puts ["<a> with multiple references:", links].join ' ' if links.size > 1
        end
        {_: :a, c: [a.delete(Contains),
                    ({_: :span, c: CGI.escapeHTML(ref.to_s.sub /^https?:..(www.)?/, '')} if ref),
                    keyval(a)]}.update(
          ref ? {href: ref,
                 class: ref.host == host ? 'local' : 'global'} : {})
      end

      def element node
        name = :div
        {_: name,                       # node
         c: [node.delete(Contains), # child nodes
             Markup[:kv][node, env]]}
      end

      def script code
        {class: :script,
         c: [{_: :span,
              style: 'font-size: 2em',
              c: :📜}]}
      end

      def document graph

        bc = String.new             # breadcrumb trail

        bgcolor = if env[:deny]     # blocked?
                    if deny_domain? # domain color
                      '#f00'
                    else            # pattern color
                      '#f80'
                    end             # status color
                  elsif StatusColor.has_key? env[:origin_status]
                    StatusColor[env[:origin_status]]
                  else
                    '#000'
                  end

        link = -> key, content { # <Link> markup
          if url = env[:links] && env[:links][key]
            [{_: :a, href: Resource.new(url).env(env).href, id: key, class: :icon, c: content},
             "\n"]
          end}

        ["<!DOCTYPE html>\n",
         {_: :html,
          c: [{_: :head,
               c: [{_: :meta, charset: 'utf-8'},

                   ({_: :title, c: CGI.escapeHTML(graph[uri][Title].join ' ')} if graph.has_key?(uri) &&
                                                                                  graph[uri].has_key?(Title)),
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
                    c: [{_: :a, id: :rootpath, href: Resource.new(join('/')).env(env).href, c: '&nbsp;' * 3}, "\n",      # 👉 root node
                        ({_: :a, id: :rehost, href: Webize::Resource(['//', ReHost[host], path].join, env).href,
                          c: {_: :img, src: ['//', ReHost[host], '/favicon.ico'].join}} if ReHost.has_key? host),
                        {_: :a, id: :UI, href: host ? uri : URI.qs(env[:qs].merge({'notransform'=>nil})), c: :🧪}, "\n", # 👉 origin UI
                        {_: :a, id: :cache, href: '/' + POSIX::Node(self).fsPath, c: :📦}, "\n",                         # 👉 cache location
                        ({_: :a, id: :block, href: '/block/' + host.sub(/^(www|xml)\./,''), class: :dimmed,              # 👉 block domain
                          c: :🛑} if host && !deny_domain?), "\n",
                        {_: :span, class: :path, c: parts.map{|p|
                           bc += '/' + p                                                                                 # 👉 path breadcrumbs
                           ['/', {_: :a, id: 'p' + bc.gsub('/','_'), class: :path_crumb,
                                  href: Resource.new(join(bc)).env(env).href,
                                  c: CGI.escapeHTML(Webize::URI(Rack::Utils.unescape p).basename || '')}]}}, "\n",
                        ([{_: :form, c: env[:qs].map{|k,v|                                                               # 🔍 search box
                             {_: :input, name: k, value: v}.update(k == 'q' ? {} : {type: :hidden})}},                   # hidden search parameters
                          "\n"] if env[:qs].has_key? 'q'),
                        env[:feeds].uniq.map{|feed|                                                                      # 👉 feed(s)
                          feed = Resource.new(feed).env env
                          [{_: :a, href: feed.href, title: feed.path, c: FeedIcon, id: 'f' + Digest::SHA2.hexdigest(feed.uri)}. # 👉 feed
                             update((feed.path||'/').match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {}), "\n"]},
                        (:🔌 if offline?),                                                                               # 🔌 offline status
                        {_: :span, class: :stats,
                         c: (elapsed = Time.now - env[:start_time] if env.has_key? :start_time                           # ⏱️ elapsed time
                             [{_: :span, c: '%.1f' % elapsed}, :⏱️, "\n"] if elapsed > 1)}]},

                   (['<br>', {class: :warning, c: env[:warnings]}] unless env[:warnings].empty?),                        # ⚠️ warnings

                   link[:up,'&#9650;'],                                                                                  # 👉 containing node

                   ({class: :redirectors,                                                                                # 👉 redirecting node(s)
                     c: [:➡️, {_: :table,
                              c: HTTP::Redirector[self].map{|r|
                                {_: :tr,
                                 c: [{_: :td, c: {_: :a, href: r.href, c: r.host}},
                                     {_: :td, c: ({_: :a, href: '/block/' + r.host.sub(/^(www|xml)\./,''), id: 'block' + Digest::SHA2.hexdigest(r.uri),
                                                   c: :🛑} unless r.deny_domain?)}]}}}]} if HTTP::Redirector[self]),

                   ({class: :referers,                                                                                   # 👉 referring node(s)
                     c: [:👉, HTML.markup(HTTP::Referer[self], env)]} if HTTP::Referer[self]),

                   graph.values.map{|v| HTML.markup v, env },                                                            # node(s)
                   #                (document[Contains].map{|v| HTML.markup v, env } if document.has_key? Contains), # child nodes

                   link[:prev,'&#9664;'], link[:down,'&#9660;'], link[:next,'&#9654;'],                                  # 👉 previous, contained and next node(s)

                   {_: :script, c: Code::SiteJS}]}]}]
      end

      def interactions counter
        if type = counter[Schema+'interactionType']
          type = type[0].to_s
          icon = Icons[type] || type
        end
        {_: :span, class: :interactionCount,
         c: [{_: :span, class: :type, c: icon},
             {_: :span, class: :count, c: counter[Schema+'userInteractionCount']}]}
      end

      def resource r

        # predicate renderer lambda
        p = -> a {property(a, r.delete(a)) if r.has_key? a}

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

        children = r.delete Contains
        color = '#' + Digest::SHA2.hexdigest(     # dest color
                  Webize::URI.new(r[To][0]).display_name)[0..5] if r.has_key?(To) &&
                                                                   r[To].size==1 &&
                                                                   Resources.member?(r[To][0].class)
        {class: :resource,                         # resource
         c: [({class: :title, c: p[Title]}.        # title
                update(ref || {}) if r.has_key? Title),
             p[Abstract], p[To],                   # abstract, dest
             (keyval r unless r.empty?),           # key/val fields
             (children.map{|c|
                markup c, env} if children),
             origin_ref,                           # origin pointer
            ]}.update(id ? {id: id} : {}).update(color ? {style: "background: repeating-linear-gradient(45deg, #{color}, #{color} 1px, transparent 1px, transparent 8px); border-color: #{color}"} : {})
      end
    end
  end
end
