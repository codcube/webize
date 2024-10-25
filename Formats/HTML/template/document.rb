module Webize
  module HTML
    class Node
      def document doc

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

        # <link> markup-generator lambda
        link = -> key, content {
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
                        "body {background-color: #{bgcolor}}"].join("\n")},

                   env[:links].map{|type, resource|
                     {_: :link, rel: type, href: CGI.escapeHTML(Resource.new(resource).env(env).href)}}]},

              {_: :body, c: [

                 # icon
                 if env[:links].has_key? :icon
                   {_: :img, class: :favicon,
                    src: env[:links][:icon].dataURI? ? env[:links][:icon].uri : env[:links][:icon].href}
                 end,

                 {class: 'top-bar', c: [

                    # 👉 toplevel node
                    {_: :a, id: :rootpath,
                     href: Resource.new(join('/')).env(env).href, c: '&nbsp;' * 3}, "\n",

                    # 👉 alternate UI
                    ({_: :a, id: :rehost,
                      href: Webize::Resource(['//', ReHost[host], path].join, env).href,
                      c: {_: :img, src: ['//', ReHost[host], '/favicon.ico'].join}} if ReHost.has_key? host),

                    # 👉 original UI/format
                    {_: :a, id: :UI, c: :🧪,
                     href: host ? uri : URI.qs(env[:qs].merge({'notransform'=>nil}))}, "\n",

                    # 👉 cache
                    {_: :a, id: :cache, c: :📦,
                     href: '/' + POSIX::Node(self).fsPath}, "\n",

                    # 👉 block domain
                    ({_: :a, id: :block, c: :🛑,
                      href: '/block/' + host.sub(/^(www|xml)\./,''),
                      class: :dimmed} if host && !deny_domain?), "\n",

                    # 👉 path breadcrumbs
                    bc = String.new,       # breadcrumb trail
                    {_: :span, class: :path, c: parts.map{|p|
                       bc += '/' + p
                       ['/', {_: :a, id: 'p' + bc.gsub('/','_'), class: :path_crumb,
                              href: Resource.new(join(bc)).env(env).href,
                              c: CGI.escapeHTML(Webize::URI(Rack::Utils.unescape p).basename || '')}]}}, "\n",

                    # 🔍 search box
                    ([{_: :form, c: env[:qs].map{|k,v|
                         {_: :input, name: k, value: v}.update(k == 'q' ? {} : {type: :hidden})}}, # parameters
                      "\n"] if env[:qs].has_key? 'q'),

                    # 👉 feed(s)
                    env[:feeds].uniq.map{|feed|
                      feed = Resource.new(feed).env env
                      [{_: :a, href: feed.href, title: feed.path, c: FeedIcon, id: 'f' + Digest::SHA2.hexdigest(feed.uri)}.
                         update((feed.path||'/').match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {}), "\n"]},

                    # 🔌 offline status
                    (:🔌 if offline?),

                    # ⏱️ elapsed time
                    {_: :span, class: :stats,
                     c: (elapsed = Time.now - env[:start_time] if env.has_key? :start_time
                         [:⏱️, {_: :span, c: '%.1f' % elapsed}, "\n"] if elapsed > 1)},

                    # 👈 referring graph(s)
                    ({class: :referers,
                      c: [HTML.markup(HTTP::Referer[self], env), :👈]} if HTTP::Referer[self]),

#                    # 👉 source graph(s)
#                    (property '#source', doc['#source'] ),
                  ]},

                 # ⚠️ warnings
                 (['<br>', {class: :warning, c: env[:warnings]}] unless env[:warnings].empty?),

                 # 👉 containing node
                 link[:up,'&#9650;'],

                 # 👉 redirecting node(s)
                 ({class: :redirectors,
                   c: [:➡️, {_: :table,
                            c: HTTP::Redirector[self].map{|r|
                              {_: :tr,
                               c: [{_: :td, c: {_: :a, href: r.href, c: r.host}},
                                   {_: :td, c: ({_: :a, href: '/block/' + r.host.sub(/^(www|xml)\./,''), id: 'block' + Digest::SHA2.hexdigest(r.uri),
                                                 c: :🛑} unless r.deny_domain?)}]}}}]} if HTTP::Redirector[self]),

                 # document-node data
                 keyval(doc),

                 {class: 'bottom-bar', c: [

                    # 👉 previous, next and expanded-set node(s)
                    link[:prev,'&#9664;'],
                    link[:next,'&#9654;'],
                    link[:down,'&#9660;'],

                    # source reference(s)
                    {class: :sources,
                     c: [
                       if doc.has_key? '#local_source'
                         [{_: :a, href: '#local_sources', c: :📦},
                          doc['#local_source'].size]
                       end,

                       if doc.has_key? '#remote_source'
                         [{_: :a, href: '#remote_sources', c: :🌍},
                          doc['#remote_source'].size]
                       end
                     ]}]},

                 # script
                 {_: :script, c: Code::SiteJS}]}]}]
      end
    end
  end
end
