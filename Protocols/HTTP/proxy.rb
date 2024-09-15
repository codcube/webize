module Webize
  class HTTP::Node

    # unproxy request/environment URLs
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
