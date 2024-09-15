module Webize
  module HTTP

    # format key/val in black&white scheme for terminal output
    def self.bwPrint(kv) = kv.map{|k,v| "\e[38;5;7;7m#{k}\e[0m#{v}\n"}

    # interface with Rack:
    # instantiate resource, call method, log response
    def self.call env
      return [403,{},[]] unless Methods.member? env['REQUEST_METHOD'] # allow HTTP methods

      env[:start_time] = Time.now                                   # start wall-clock timer
      env['SERVER_NAME'].downcase!                                  # normalize hostname case
      env.update HTTP.env                                           # init environment fields

      isPeer = PeerHosts.has_key? env['SERVER_NAME']                # peer node?
      isLocal = LocalAddrs.member?(PeerHosts[env['SERVER_NAME']] || env['SERVER_NAME']) # local node?
      env[:proxy_refs] = isPeer || isLocal                          # emit proxy refs on local and peer hosts

      u = RDF::URI(isLocal ? '/' : [isPeer ? :http : :https, '://', env['HTTP_HOST']].join). # base URI
            join RDF::URI(env['REQUEST_PATH']).path                 # enforce just path in REQUEST_PATH variable

      env[:base] = (Node u, env).freeze                             # base node - immutable
      uri = Node u, env                                             # request node - may update for concrete-representations/variants or relocations

      if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?         # query?
        env[:qs] = Webize::URI('?'+env['QUERY_STRING']).query_hash  # parse and memoize query
        qs = env[:qs].dup                                           # query args
        Args.map{|k|                                                # (💻 <> 🖥) internal args to request environment
         env[k.to_sym] = qs.delete(k) || true if qs.has_key? k}
        uri.query_values = qs unless qs.empty?                      # (🖥 <> ☁️) external args to request URI
      end

      if env['HTTP_REFERER']
        env[:referer] = Node(env['HTTP_REFERER'], env)              # referer node
        Referer[env[:base]] ||= []
        Referer[env[:base]].push env[:referer] unless Referer[env[:base]].member? env[:referer]
      end

      Console.logger.debug ["\e[7m HEAD \e[0m #{uri}\n", HTTP.bwPrint(env)].join if debug?

      URI.blocklist if env['HTTP_CACHE_CONTROL'] == 'no-cache'      # refresh blocklist (ctrl-shift-R in client UI)

      uri.send(env['REQUEST_METHOD']).yield_self{|status,head,body| # call request and log response
        inFmt = MIME.format_icon env[:origin_format]                # input format
        outFmt = MIME.format_icon head['Content-Type']              # output format
        color = env[:deny] ? '38;5;196' : (MIME::Color[outFmt]||0)  # format -> color

        Console.logger.info [(env[:base].scheme == 'http' && !isPeer) ? '🔓' : nil, # denote transport security

             if env[:deny]                                          # action taken:
               '🛑'                                                 # blocked
             elsif StatusIcon.has_key? status
               StatusIcon[status]                                   # status code
             elsif ActionIcon.has_key? env['REQUEST_METHOD']
               ActionIcon[env['REQUEST_METHOD']]                    # HTTP method
             elsif uri.offline?
               '🔌'                                                 # offline response
             end,

             (ENV.has_key?('http_proxy') ? '🖥' : '🐕' if env[:fetched]),    # upstream type: origin or proxy/middlebox

             env[:referer] ? ["\e[#{color}m",
                              env[:referer].display_host,
                              "\e[0m → "] : nil,  # referer

             outFmt, ' ',                                                     # output format

             "\e[#{color}#{';7' if env[:referer]&.host != env[:base].host}m", # off-site referer

             (env[:base].display_host unless env[:referer]&.host == env[:base].host), env[:base].path, "\e[0m", # host, path

             ([' ⟵ ', inFmt, ' '] if inFmt && inFmt != outFmt),             # input format, if transcoded

             (qs.map{|k,v|
                " \e[38;5;7;7m#{k}\e[0m #{v}"} if qs && !qs.empty?),         # query arguments

             head['Location'] ? [" → \e[#{color}m",
                                 (Node head['Location'], env).unproxyURI,
                                 "\e[0m"] : nil,                             # redirect target

            ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join

        [status, head, body]}                                                # response
    rescue Exception => e
      Console.logger.failure uri, e
      [500, {'Content-Type' => 'text/html; charset=utf-8'},
       uri.head? ? [] : ["<html><body class='error'>#{HTML.render({_: :style, c: Webize::CSS::Site})}500</body></html>"]]
    end

    def self.decompress head, body
      encoding = head.delete 'Content-Encoding'
      return body unless encoding
      case encoding.to_s
      when /^br(otli)?$/i
        Brotli.inflate body
      when /gzip/i
        (Zlib::GzipReader.new StringIO.new body).read
      when /flate|zip/i
        Zlib::Inflate.inflate body
      else
        head['Content-Encoding'] = encoding
        body
      end
    rescue Exception => e
      Console.logger.failure head, e
      head['Content-Encoding'] = encoding
      body
    end

  end
  class HTTP::Node

    def GET
      return hostGET if host                  # remote node
      ps = parts                              # parse path
      p = ps[0]                               # find first node in path
      return fetchLocal unless p              # local node - empty or root path
      return unproxy.hostGET if p[-1] == ':' && ps.size > 1        # remote node - proxy URI with scheme
      return unproxy.hostGET if p.index('.') && p != 'favicon.ico' # remote node - proxy URI sans scheme
      return dateDir if %w{m d h y}.member? p # redirect to current year/month/day/hour container
      return block parts[1] if p == 'block'   # block domain
      return redirect '/d?f=msg*' if path == '/mail' # email inbox
      return fetch uris if extname == '.u' && query == 'fetch' # remote node(s) in URI list
      fetchLocal                                               # local node
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
