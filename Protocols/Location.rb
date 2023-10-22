module Webize

  # declarative host categories
  CDN_hosts = Webize.configRegex 'hosts/CDN'
  FWD_hosts = Webize.configHash 'hosts/forward'
  URL_hosts = Webize.configList 'hosts/url'
  RSS_hosts = Webize.configList 'hosts/rss'
  YT_hosts = Webize.configList 'hosts/youtube'

  class URI

    def relocate?
      URL_host? ||
        RSS_available? ||
        (CDN_doc? && deny_domain?) ||
        [FWD_hosts, YT_hosts].find{|_| _.member? host}
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
                 elsif CDN_doc? && deny_domain?
                   ['//', CDN_host, ':', CDN_port, '/', host, path, query ? ['?', query] : nil].join
                 else
                   self
                  end)
    end

    def URL_host?
      URL_hosts.member?(host) ||                               # explicit URL rehoster
        (host&.match?(CDN_hosts) && (query_values||{}).has_key?('url')) # URL rehost on CDN host
    end

  end
  class Resource

    # reference in current context
    def href
      return '#' + fragment if in_doc? && fragment                       # relativized fragment reference
      return uri unless host && env[:proxy_hrefs] && !proxy_reference?   # URI (identifier) as URL (locator)
      ['http://', env['HTTP_HOST'], '/', scheme ? uri : uri[2..-1]].join # proxy reference
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

    def proxy_reference?
      [CDN_host,
       env['SERVER_NAME']].member? host
    end

    def relocate
      Resource super
    end

  end
end
