module Webize

  # declarative host categories
  CDN_hosts = Webize.configRegex 'hosts/CDN'
  FWD_hosts = Webize.configHash 'hosts/forward'
  URL_hosts = Webize.configList 'hosts/url'
  RSS_hosts = Webize.configList 'hosts/rss'
  YT_rehosts = Webize.configList 'formats/video/rehost-yt'
  YT_host = 'www.youtube.com'

  # addressing
  LocalAddrs = Socket.ip_address_list.map &:ip_address # local addresses
  PeerHosts = Hash[*File.open([ENV['PREFIX'],'/etc/hosts'].join).readlines.map(&:chomp).grep_v(/^#/).map{|l|
                     addr, *names = l.split            # parse hostname list
                     names.map{|host|
                       [host, addr]}}.flatten]         # hostname -> address table
  PeerAddrs = PeerHosts.invert                         # address -> hostname table

  # cache-configuration options

  # local cache - accepts shutoff argument
  Local_Cache = !%w(0 false no off).member?(
    (ENV['MEDIA_CACHE'] || 'ON').downcase) # (on by default)

  # peer cache - accepts base-URI argument
  Remote_Cache = ENV['CDN']

  class URI

    def relocate? = (URL_host? && (query_hash['url'] || query_hash['u'])) ||
                    RSS_available? ||
                    [FWD_hosts, YT_rehosts].find{|_| _.member? host} ||
                    (YT_host == host && parts[0] == 'v')

    def relocate
      Webize::URI(if URL_host? && (query_hash['url'] || query_hash['u'])
                  query_hash['url'] || query_hash['u']
                 elsif FWD_hosts.member? host
                   ['//', FWD_hosts[host], path, query ? ['?', query] : nil].join
                 elsif RSS_available?
                   ['//', host, path ? path.sub(/\/$/,'') : '/', '.rss'].join
                 elsif [YT_host, *YT_rehosts].member? host
                   ['https://www.youtube.com/watch?v=',
                    query_hash['v'] || parts[-1]].join
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

    # 👉 graph, for reachability in recursive walk, lookup, treeization, etc algorithms
    # 
    # classic example: https://en.wikipedia.org/wiki/Seven_Bridges_of_K%C3%B6nigsberg
    # RDF formalisms&guidelines: https://www.w3.org/submissions/CBD/ https://patterns.dataincubator.org/book/graph-per-source.html
    def graph_pointer graph, tabular = false
      containment = tabular ? Schema + 'item' : Contains

      container = fsNames.inject(base) do |parent, name| # walk from base to graph via hierarchical containers
        c = RDF::URI('#container_' + Digest::SHA2.hexdigest(parent.to_s + name)) # container URI
        graph << RDF::Statement.new(parent, RDF::URI(containment), c) # parent 👉 child
        graph << RDF::Statement.new(c, RDF::URI(Title), name) # container name
        c                                                     # child
      end

      graph << RDF::Statement.new(container, RDF::URI(containment), self) # container 👉 graph
    end

    # resource reference in current browsing context
    def href
      return '/' + fsPath if %w(cid mid tag).member?(scheme)
      return '#' + fragment if fragment && in_request_graph? # relative fragment
      return to_s unless host                                # relative path
      return proxy_ref if env[:proxy_refs] && !proxy_ref?    # proxy locator
      to_s                                                   # URI (identifier) == URL (locator)
    end

    # set scheme to HTTP. only advised for peer nodes on local/private/VPN networks
    def insecure
      return self if scheme == 'http'
      _ = dup.env env
      _.scheme = 'http'
      _.env[:base] = _
    end

    # is URI canonical location in request graph?
    def in_request_graph? = on_host? && on_path?

    # local aka fragment identifier
    # synthesize a derived local identifier if remote resource
    def local_id = in_request_graph? ? ( fragment || '' ) : 'inline_' + Digest::SHA2.hexdigest(to_s)

    # test for canonical location on base host/path - unspecified matches due to relative resolution
    def on_host? = !host || env[:base].host == host # unspecified or matching host
    def on_path? = !path || env[:base].path == path # unspecified or matching path

    def offline? = ENV.has_key?('OFFLINE') || env[:qs].has_key?('offline')

    # relocate reference to proxy host
    def proxy_ref = ['http://', env['HTTP_HOST'], '/', scheme ? uri : uri[2..-1]].join

    # is reference located on proxy?
    def proxy_ref? = env['SERVER_NAME'] == host

    # relocate preserving environment of Resource instance
    def relocate = Resource super

  end
end
