module Webize

  # declarative host categories
  CDN_hosts = Webize.configRegex 'hosts/CDN'
  FWD_hosts = Webize.configHash 'hosts/forward'
  URL_hosts = Webize.configList 'hosts/url'
  RSS_hosts = Webize.configList 'hosts/rss'
  YT_hosts = Webize.configList 'hosts/youtube'

  # addressing
  LocalAddrs = Socket.ip_address_list.map &:ip_address # local addresses
  PeerHosts = Hash[*File.open([ENV['PREFIX'],'/etc/hosts'].join).readlines.map(&:chomp).grep_v(/^#/).map{|l|
                     addr, *names = l.split            # parse hostname list
                     names.map{|host|
                       [host, addr]}}.flatten]         # hostname -> address table
  PeerAddrs = PeerHosts.invert                         # address -> hostname table

  class URI

    def relocate? = URL_host? || RSS_available? || [FWD_hosts, YT_hosts].find{|_| _.member? host} || filter_allow?

    def relocate
      Webize::URI(if URL_host?
                  q = query_hash
                  q['url'] || q['u'] || q['q'] || self
                 elsif FWD_hosts.member? host
                   ['//', FWD_hosts[host], path, query ? ['?', query] : nil].join
                 elsif RSS_available?
                   ['//', host, path.sub(/\/$/,''), '.rss'].join
                 elsif YT_hosts.member? host
                   ['//www.youtube.com/watch?v=',
                    query_hash['v'] || path[1..-1]].join
                 elsif filter_allow? # filtered domain. relocate to unfiltered node for selective egress
                   ['//localhost:8000/', host, path, query ? ['?', query] : nil].join
                 else
                   self
                  end)
    end

    def URL_host?
      URL_hosts.member?(host) ||                       # explicit URL rehost domain
        (host&.match?(CDN_hosts) && query_hash.has_key?('url')) # URL rehost on CDN domain
    end

  end
  class Resource

    # resolve reference to current request context
    def href
      return '#' + fragment if fragment && in_doc?     # relativized fragment
      return uri unless host                           # relative path
      return proxy_ref if env[:proxy_refs] && !proxy_ref? # proxied locator
      uri                                              # identifier URI as locator URL (default)
    end

    # set scheme to HTTP for peer nodes on private/VPN networks
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

    def proxy_ref = ['http://', env['HTTP_HOST'], '/', scheme ? uri : uri[2..-1]].join

    def proxy_ref? = env['SERVER_NAME'] == host

    def relocate
      Resource super
    end

  end
end
