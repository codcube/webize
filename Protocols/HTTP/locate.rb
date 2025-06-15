module Webize
  class HTTP::Node


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


    def notfound
      env[:origin_status] ||= 404
      respond [RDF::Repository.new]
    end

    def redirect(location) = [302, {'Location' => location}, []]

    # unproxy request and environment URIs
    def unproxy
      r = unproxyURI                                            # unproxied URI
      r.scheme ||= 'https'                                      # set default scheme
      r.host = r.host.downcase if r.host.match? /[A-Z]/         # normalize hostname
      env[:base] = Node r.uri                                   # update base URI
      if env[:referer] # update referer URI
        env[:referer] = env[:referer].unproxyURI
        env['HTTP_REFERER'] = env[:referer].to_s
      end
      r
    end

    # proxy URI -> canonical URI
    def unproxyURI
      p = parts[0]
      return self unless p&.index /[\.:]/ # scheme or DNS name required
      Node [(p && p[-1] == ':') ? path[1..-1] : ['/', path], query ? ['?', query] : nil].join
    end

  end
end
