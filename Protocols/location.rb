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

    def relocate? = URL_host? || RSS_available? || [FWD_hosts, YT_hosts].find{|_| _.member? host} || filtered_allow?

    def relocate
      Webize::URI(if URL_host?
                  q = query_hash
                  q['url'] || q['u'] || self
                 elsif FWD_hosts.member? host
                   ['//', FWD_hosts[host], path, query ? ['?', query] : nil].join
                 elsif RSS_available?
                   ['//', host, path.sub(/\/$/,''), '.rss'].join
                 elsif YT_hosts.member? host
                   ['//www.youtube.com/watch?v=',
                    query_hash['v'] || path[1..-1]].join
                 elsif filtered_allow? # redirect to egress port
                   ['//', env['SERVER_NAME'], ':8000/', host, path, query ? ['?', query] : nil].join
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

    # resolve reference for current browsing context
    def href
      return '#' + fragment if fragment && in_doc?        # relative fragment
      return uri unless host                              # relative path
      return proxy_ref if env[:proxy_refs] && !proxy_ref? # proxy locator
      uri                                                 # identifier URI as locator URL (default)
    end

    # set scheme to HTTP. only advised for peer nodes on local/private/VPN networks
    def insecure
      return self if scheme == 'http'
      _ = dup.env env
      _.scheme = 'http'
       _.env[:base] = _
    end

    # is URI in request graph?
    def in_doc? = on_host? && env[:base].path == path

    # is URI on request host?
    def on_host? = env[:base].host == host

    def offline? = ENV.has_key? 'OFFLINE'

    # relocate reference to proxy host
    def proxy_ref = ['http://', env['HTTP_HOST'], '/', scheme ? uri : uri[2..-1]].join

    # is reference located on proxy?
    def proxy_ref? = env['SERVER_NAME'] == host

    # relocate preserving environment of Resource instance
    def relocate = Resource super

  end
end
