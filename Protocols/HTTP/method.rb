module Webize
  class HTTP::Node

    def GET
      return hostGET if host     # remote node

      ps = parts                 # path nodes
      p = ps[0]                  # first node

      return fetchLocal unless p # local node - void or root path
                                 # proxy URI
      return unproxy.hostGET if (p[-1] == ':' && ps.size > 1) || # remote node, URI w/ scheme
                                (p.index('.') && p != 'favicon.ico') #            sans scheme

      return dateDir if %w{m d h y}.member? p # current year/month/day/hour contents
      return block parts[1] if p == 'block'   # block domain
      return redirect '/d?f=msg*' if path == '/mail' # email

      if extname == '.u' # URI list
        case query
        when 'fetch'     # remote node(s)
          return fetch uris
        when 'load'      # cached node(s)
          return fetchLocal uris
        end
      end

      fetchLocal         # local node(s)
    end

    def HEAD = self.GET.yield_self{|s, h, _|
                                   [s, h, []]} # status + header only

    def OPTIONS
      env[:deny] = true
      [202, {'Access-Control-Allow-Credentials' => 'true',
             'Access-Control-Allow-Headers' => %w().join(', '),
             'Access-Control-Allow-Origin' => origin}, []]
    end

    def POST
      env[:deny] = true
      [202, {'Access-Control-Allow-Credentials' => 'true',
             'Access-Control-Allow-Origin' => origin}, []]
    end

    def block domain
      File.open([Webize::ConfigPath, :blocklist, :domain].join('/'), 'a'){|list|
        list << domain << "\n"} # add to blocklist
      URI.blocklist             # read blocklist
      redirect Node(['//', domain].join).href
    end

    def deny
      status = 403
      env[:deny] = true
      env[:warnings].push({_: :a,
                           id: :allow,
                           title: 'allow temporarily',
                           style: 'font-size: 3em',
                           href: Node(['//', host, path, '?allow=', allow_key].join).href,
                           c: :👁️})

      if uri.match? Gunk

        hilite = '<span style="font-size:1.2em; font-weight: bold; background-color: #f00; color: #fff">'
        unhilite = '</span>'

        if query&.match? Gunk # drop query
          env[:warnings].push ['pattern block in query:<br>',
                               {_: :a,
                                id: :noquery,
                                title: 'URI without query',
                                href: Node(['//', host, path].join).href,
                                c: [host, path], style: 'background-color: #000; color: #fff'},
                               '?',
                               query.gsub(Gunk){|m|
                                 [hilite, m, unhilite].join }]
        else
          env[:warnings].push ['pattern block in URI:<br>',
                               uri.gsub(Gunk){|m|
                                 [hilite, m, unhilite].join}]
        end

        env[:warnings].push({_: :dl, # key/val view of query args
                             c: query_values.map{|k, v|
                               vs = v.class == Array ? v : [v]
                               [{_: :dt, c: HTML.markup(k, env)},
                                vs.map{|v|
                                  {_: :dd, c: HTML.markup(v.match(/^http/) ? RDF::URI(v) : v, env)} if v
                                }]}}) if query
      end

      ext = File.extname basename if path

      type, content = if ext == '.css'
                        ['text/css', '']
                      elsif fontURI?
                        ['font/woff2', HTML::SiteFont]
                      elsif imgURI?
                        ['image/png', HTML::SiteIcon]
                      elsif ext == '.js'
                        ['application/javascript', "// URI: #{uri.match(Gunk) || host}"]
                      elsif ext == '.json'
                        ['application/json','{}']
                      else
                        ['text/html; charset=utf-8', RDF::Repository.new.dump(:html, base_uri: self)]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => origin,
        'Content-Type' => type},
       head? ? [] : [content]]
    end

    def dropQS
      if !query                         # URL is query-free
        fetch.yield_self{|s,h,b|        # call origin
          h.keys.map{|k|                # strip redirected-location query
            if k.downcase == 'location' && h[k].match?(/\?/)
              Console.logger.info "dropping query from #{h[k]}"
              h[k] = h[k].split('?')[0]
            end
          }
          [s,h,b]}                        # response
      else                                # redirect to no-query location
        Console.logger.info "dropping query from #{uri}"
        redirect Node(['//', host, path].join).href
      end
    end

    def hostGET
      return [301, {'Location' => relocate.href}, []] if relocate? # relocated node
      if path == '/feed' && adapt? && Feed::Subscriptions[host]    # aggregate feed node - doesn't exist on origin server
        return fetch Feed::Subscriptions[host]
      end
      dirMeta              # 👉 adjacent nodes
      return deny if deny? # blocked node
      fetch                # remote node
    end

    def notfound
      env[:origin_status] = 404
      respond [RDF::Repository.new]
    end

    def redirect(location) = [302, {'Location' => location}, []]

  end
end
