module Webize
  module HTTP

    # format (key, val) in black&white scheme for terminal output
    def self.bwPrint(kv) = kv.map{|k,v|
      "\e[38;5;7;7m#{k}\e[0m#{v}\n"}

    # Rack-caller entry-point
    def self.call env
      return [403,{},[]] unless Methods.member? env['REQUEST_METHOD'] # allow HTTP methods

      # instantiate resource, call method, log response:

      env[:start_time] = Time.now                                   # start wall-clock timer
      env['SERVER_NAME'].downcase!                                  # normalize hostname
      env.update HTTP.env                                           # init environment fields

      peerURL = PeerHosts.has_key? env['SERVER_NAME']               # peer node?
      localURL = ENV['HOSTNAME'] == env['SERVER_NAME'] ||           # local node?
                 LocalAddrs.member?(PeerHosts[env['SERVER_NAME']] || # hostname->address result is local address
                                    env['SERVER_NAME'])              # local address

      env[:proxy_refs] = peerURL || localURL                        # prefer to emit refs proxied onto local and peer base URI

      u = RDF::URI(localURL ? '/' : [peerURL ? :http : :https, '://', env['HTTP_HOST']].join). # base URI
            join RDF::URI(env['REQUEST_PATH']).path                 # enforce just a path in REQUEST_PATH - full URI appears there sometimes from upstream libraries/sources

      env[:base] = (Node u, env).freeze                             #    base URI - immutable
      uri = Node u, env                                             # request URI - updateable at req-time for representation-variants or relocations
      uri.query = env['QUERY_STRING'] if env['QUERY_STRING'] &&     # query
                                        !env['QUERY_STRING'].empty?
      env[:qs] = uri.query_hash                                     # parse and memoize query

      if env['HTTP_REFERER']
        env[:referer] = Node(env['HTTP_REFERER'], env)              # referer
        Referer[env[:base]] ||= []
        Referer[env[:base]].push env[:referer] unless Referer[env[:base]].member? env[:referer]
      end

      Console.logger.debug ["\e[7m HEAD \e[0m #{uri}\n", HTTP.bwPrint(env)].join if debug?

      URI.blocklist if env['HTTP_CACHE_CONTROL'] == 'no-cache'      # refresh blocklist (ctrl-shift-R in client UI)

      uri.send(env['REQUEST_METHOD']).yield_self{|status,head,body| # call request and log response
        inFmt = MIME.format_icon env[:origin_format]                # input format
        outFmt = MIME.format_icon head['Content-Type']              # output format
        color = env[:deny] ? '38;5;196' : (MIME::Color[outFmt]||0)  # format -> color

        Console.logger.info [(env[:base].scheme == 'http' && !peerURL) ? '🔓' : nil, # denote transport insecurity

             if env[:deny]                                          # action taken:
               '🛑'                                                 # blocked
             elsif StatusIcon.has_key?(status) && status != 200
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

             env[:qs].map{|k,v|                                              # query arguments
                " \e[38;5;7;7m#{k}\e[0m #{v}"},

             head['Location'] ? [" → \e[#{color}m",
                                 (Node head['Location'], env).unproxyURI,
                                 "\e[0m"] : nil,                             # redirect target

            ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join

        [status, head, body]}                                                # response
    end

  end
end
