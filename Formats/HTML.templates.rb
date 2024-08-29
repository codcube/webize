module Webize
  module HTML
    class Property
 
      # property URI -> markup method
      Markup = Webize.configHash 'HTML/property'

      # property-markup methods

      def abstract as
        {class: :abstract,
         c: as.map{|a| [(HTML.markup a, env), ' ']}}
      end

      def buttons resources
        [{_: :style, c: "a.button {background-color: ##{Digest::SHA2.hexdigest(uri)[0..5]}; color: white}"},

         resources.map{|r|
           uri = Webize::Resource r['uri'], env

           {_: :a,
            href: uri.href,
            id: 'b' + Digest::SHA2.hexdigest(rand.to_s),
            class: :button,
            c: uri.display_name}}]
      end

      def cache locations
        locations.map{|l|
          {_: :a, href: '/' + l.fsPath, c: :📦}}
      end

      def creator creators
        creators.map{|creator|
          if Identifiable.member? creator.class
            uri = Webize::Resource.new(creator).env env
            name = uri.display_name
            color = Digest::SHA2.hexdigest(name)[0..5]
            {_: :a, class: :from, href: uri.href, style: "background-color: ##{color}", c: name}
          else
            HTML.markup creator, env
          end}
      end

      # graph index - we're essentially adding more triples at a late stage just before view rendering
      # if we want to use these pointers via Turtle, we'll want a 'graph annotation pass' earlier
      def graph_index nodes

        nodes.map{|node|
          # for remote graphs,
          next unless uri = node['uri']
          uri = Webize::Resource uri, env
          next unless uri.host

          # add pointers to upstream, cached (TODO historical) versions
          node.update({'#cache' => [POSIX::Node(uri)],
                       '#origin' => [uri],
                      })}

        index_table nodes
      end

      def identifier uris
        (uris.class == Array ? uris : [uris]).map{|uri|
          {_: :a, c: :🔗,
           href: env ? Webize::Resource(uri, env).href : uri,
           id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}
      end

      # table of nodes without an inlined display of their full content
      # as w/ #graph_index we may create pointers to e.g. in-doc representations
      def index_table(nodes) = table nodes, skip: [Contains]

      def origin locations
        locations.map{|l|
          {_: :a, href: l.uri, c: :↗, class: :origin, target: :_blank}}
      end

      def rdf_type types
        types.map{|t|
          t = Webize::Resource t.class == Hash ? t['uri'] : t, env
          {_: :a, class: :type, href: t.href,
           c: if t.uri == Contains
            nil
          elsif Icons.has_key? t.uri
            Icons[t.uri]
          else
            t.display_name
           end}}
      end

      def table graph, skip: []
        case graph.size
        when 0 # empty
          nil
        when 1 # key/val table of singleton resource
          Node.new(env[:base]).env(env).keyval graph[0], skip: skip
        else   # tabular render of resources
          keys = graph.map(&:keys).flatten.uniq -
                 skip                        # apply property skiplist

          {_: :table, class: :tabular,       # table
           c: [({_: :thead,
                 c: {_: :tr, c: keys.map{|p| # table heading
                       p = Webize::URI(p)
                       slug = p.display_name
                       icon = Icons[p.uri] || slug
                       [{_: :th,             # ☛ sorted columns
                         c: {_: :a, c: icon,
                             href: URI.qs(env[:qs].merge({'sort' => p.uri,
                                                          'order' => env[:order] == 'asc' ? 'desc' : 'asc'}))}}, "\n"]}}} if env),
               {_: :tbody,
                c: graph.map{|resource|      # resource -> row
                  [{_: :tr, c: keys.map{|k|
                      [{_: :td, property: k,
                        c: (Property.new(k).env(env).markup(resource[k]) if resource.has_key? k)},
                       "\n" ]}}, "\n" ]}}]}
        end
      end

      def title titles
        titles.map{|t|
          {_: :span, c: HTML.markup(t, env)}}
      end

      def to recipients
        recipients.map{|r|
          if Identifiable.member? r.class
            uri = Webize::Resource.new(r).env env
            name = uri.display_name
            color = Digest::SHA2.hexdigest(name)[0..5]
            {_: :a, class: :to, href: uri.href, style: "background-color: ##{color}", c: ['&rarr;', name].join}
          else
            HTML.markup r, env
          end}
      end
    end

    class Node

      # type URI -> markup method
      Markup = Webize.configHash 'HTML/resource'

      # markup methods - for most types we parameterize default renderer with DOM-node name

      def p(node) = resource node, :p

      def ul(node) = resource node, :ul
      def ol(node) = resource node, :ol
      def li(node) = resource node, :li

      def h1(node) = resource node, :h1
      def h2(node) = resource node, :h2
      def h3(node) = resource node, :h3
      def h4(node) = resource node, :h4
      def h5(node) = resource node, :h5
      def h6(node) = resource node, :h6

      def table(node) = resource node, :table
      def thead(node) = resource node, :thead
      def tfoot(node) = resource node, :tfoot
      def th(node) = resource node, :th
      def tr(node) = resource node, :tr
      def td(node) = resource node, :td

      # anchor
      def a _
        _.delete Type

        if content = (_.delete Contains)
          content.map!{|c|
            HTML.markup c, env}
        end

        links = _.delete Link

        if title = (_.delete Title)
          title.map!{|c|
            HTML.markup c, env}
        end

        attrs = keyval _ unless _.empty? # remaining attributes

        links.map{|ref|
          ref = Webize::URI(ref['uri']) if ref.class == Hash
          {class: :link,
           c: [{_: :a, href: ref,
                class: ref.host == host ? 'local' : 'global',
                c: [title,
                    {_: :span, c: CGI.escapeHTML(ref.to_s.sub /^https?:..(www.)?/, '')}]},
               content, attrs]}} if links
      end

      def document doc
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

                   ({_: :title, c: CGI.escapeHTML(doc[Title].join ' ')} if doc.has_key? Title),
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

                   if doc.has_key? Contains
                     doc[Contains].map{|v| HTML.markup v, env }
                   end, # child nodes

                   keyval(doc, skip: [Contains]), # document attributes

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

      def keyval kv, skip: []
        [{_: :dl,
          c: kv.map{|k, vs|
            {c: [{_: :dt, c: property(Type, [k])}, "\n",
                 {_: :dd, c: property(k, vs)}, "\n"]} unless skip.member? k
          }},
         "\n"]
      end

      def resource r, type = :div
        shown = ['#new', 'uri', Title, Abstract, To, Contains]

        p = -> a {                                # property-render indirection to skip empty/nil fields (lambda)
          property(a, r[a]) if r.has_key? a}

        if uri = r['uri']                         # identified node:
          uri = Webize::Resource(uri, env)        # URI
          id = uri.local_id                       # localized fragment identity (representation of transcluded resource in document)

          origin_ref = {_: :a, class: :pointer,   # origin pointer
                        href: uri, c: :🔗}
          ref = {_: :a, href: uri.href,           # pointer
                 id: 'p'+Digest::SHA2.hexdigest(rand.to_s)}
        end

        color = if r.has_key? '#new'              # new resource
                  '#8aa'
                elsif r.has_key?(To) && Identifiable.member?(r[To][0].class)
                  '#' + Digest::SHA2.hexdigest(   # message-dest color
                    Webize::URI.new(r[To][0]).display_name)[0..5]
                elsif uri
                  if uri.deny?                    # blocked resource
                    :red
                  elsif HostColor.has_key? uri.host
                    HostColor[uri.host]           # host color
                  end
                end

        [{_: type,                                # node
          c: [({class: :title,                    # title
                c: r[Title].map{|t|
                  HTML.markup t, env}}.
                 update(ref || {}) if r.has_key? Title),
              p[Abstract], p[To],                 # abstract, dest
              "\n", keyval(r, skip: shown),       # key/val fields
              (r[Contains].map{|c|
                 HTML.markup c, env} if r[Contains]),
              origin_ref,                         # origin pointer
             ]}.
           update(id ? {id: id} : {}).
           update((id && type == :div) ? {class: :resource} : {}).
           update(color ? {style: "background: repeating-linear-gradient(#{45 * rand(8)}deg, #{color}, #{color} 1px, transparent 1px, transparent 28px); border-color: #{color}"} : {}), "\n"]
      end
    end
  end
end
