module Webize
  module HTML

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

                               ({class: :redirectors,
                                 c: [:➡️, {_: :table,
                                          c: HTTP::Redirector[env[:base]].map{|r|
                                            {_: :tr,
                                             c: [{_: :td, c: {_: :a, href: r.href, c: r.host}},
                                                 {_: :td, c: ({_: :a, href: '/block/' + r.host.sub(/^(www|xml)\./,''), class: :dimmed, c: :🛑} unless r.deny_domain?)}]}}}]} if HTTP::Redirector[env[:base]]), # redirect sources

                               ({class: :referers,
                                 c: [:👉, HTML.markup(HTTP::Referer[env[:base]], env)]} if HTTP::Referer[env[:base]]),       # referer sources

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
             ({_: :a, id: :block, href: '/block/' + host.sub(/^(www|xml)\./,''), class: :dimmed,                           # 👉 block domain action
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
  end
end
