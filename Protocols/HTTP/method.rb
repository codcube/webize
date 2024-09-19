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
        when 'list'      # node list
          return fetchLocal uris.map &:preview
        when 'load'      # cached node(s)
          return fetchLocal uris
        end
      end

      fetchLocal         # local node(s)
    end

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

  end
end
