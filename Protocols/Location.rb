module Webize
  class URI

    def relocate?
      URL_host? ||
        RSS_available? ||
        [FWD_hosts,
         YT_hosts].find{|group|
        group.member? host}
    end

    def relocate
      Webize::URI(if URL_host?
                  q = query_values || {}
                  q['url'] || q['u'] || q['q'] || self
                 elsif FWD_hosts.member? host
                   ['//', FWD_hosts[host], path].join
                 elsif RSS_available?
                   ['//', host, path.sub(/\/$/,''), '.rss'].join
                 elsif YT_hosts.member? host
                   ['//www.youtube.com/watch?v=',
                    (query_values || {})['v'] || path[1..-1]].join
                 else
                   self
                  end)
    end

  end
  class Resource

    # resolve URI for current environment/context
    def href
      if in_doc? && fragment # local reference
        '#' + fragment
      elsif env[:proxy_href] # proxy reference:
        if !host || env['SERVER_NAME'] == host
          uri                #  local node
        else                 #  remote node
          ['http://', env['HTTP_HOST'], '/', scheme ? uri : uri[2..-1]].join
        end
      else                   # direct URI<>URL map
        uri
      end
    end

    # set scheme to HTTP for fetch method/library protocol selection for peer nodes on private/local networks
    def insecure
      return self if scheme == 'http'
      _ = dup.env env
      _.scheme = 'http'
       _.env[:base] = _
    end

    def in_doc?  # is URI in request graph?
      on_host? && env[:base].path == path
    end

    def on_host? # is URI on request host?
      env[:base].host == host
    end

    def offline?
      ENV.has_key? 'OFFLINE'
    end

    def relocate
      Resource super
    end

    def RSS_available?
      RSS_hosts.member?(host) &&
        !path.index('.rss') &&
        parts[0] != 'gallery'
    end

    def URL_host?
      URL_hosts.member?(host) ||                               # explicit URL rehoster
        (host&.match?(CDN_hosts) && (query_values||{}).has_key?('url')) # URL rehost on CDN host
    end

  end
end
