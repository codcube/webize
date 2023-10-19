module Webize
  class URI

    def relocate?
      url_host? || RSS_available? ||
        [FWD_hosts,
         YT_hosts].find{|group|
        group.member? host}
    end

    def relocate
      Webize::URI(if url_host?
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

    def offline?
      ENV.has_key? 'OFFLINE'
    end

    def relocate
      Resource super
    end

  end
end
