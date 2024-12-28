module Webize
  module HTTP

    # format (key, val) in black&white scheme for terminal output
    def self.bwPrint(kv) = kv.map{|k,v|
      "\e[38;5;7;7m#{k}\e[0m#{v}\n"}

    # Rack-caller entry-point
    def self.call env
      return [403,{},[]] unless Methods.member? env['REQUEST_METHOD'] # allow HTTP methods
      env[:start_time] = Time.now                                   # start wall-clock timer
      env.update HTTP.env                                           # init environment fields

      env['SERVER_NAME'].downcase!                                  # normalize hostname-case
      peerURL = PeerHosts.has_key? env['SERVER_NAME']               # peer node?
      localURL = ENV['HOSTNAME'] == env['SERVER_NAME'] ||           # local node?
                 LocalAddrs.member?(PeerHosts[env['SERVER_NAME']] || # hostname->address mapping is local address
                                    env['SERVER_NAME'])              # local address

      env[:proxy_refs] = peerURL || localURL                        # enable proxy references on local and peer (re)hosts - pure URI-rewriting alternative to HTTP_PROXY app variables

      base = RDF::URI(localURL ? '/' : [peerURL ? :http : :https, '://', # scheme
                                        env['HTTP_HOST']].join).    # host
               join RDF::URI(env['REQUEST_PATH']).path              # path - REQUEST_PATH may contain a full URI (mainly on HTTP2 or Gemini frontend)

      env[:base] = (Node base, env).freeze                          # base URI    - immutable environment value
      uri = Node base, env                                          # request URI - updateable at req-time for representation-variants or relocations

      uri.query = env['QUERY_STRING'] if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?
      env[:qs] = uri.query_hash                                     # query arguments

      if env['HTTP_REFERER']                                        # referer
        env[:referer] = Node(env['HTTP_REFERER'], env)
        Referer[env[:base]] ||= []
        Referer[env[:base]].push env[:referer] unless Referer[env[:base]].member? env[:referer]
      end

      Console.logger.debug ["\e[7m HEAD \e[0m #{uri}\n", HTTP.bwPrint(env)].join if debug?

      URI.blocklist if env['HTTP_CACHE_CONTROL'] == 'no-cache'      # refresh blocklist (ctrl-shift-R in client UI)

      uri.send(env['REQUEST_METHOD']).yield_self{|status,head,body| # call request method
                                                                    # log response
        inFmt = MIME.format_icon env[:origin_format]                # input format
        outFmt = MIME.format_icon head['Content-Type']              # output format
        color = env[:deny] ? '38;5;196' : (MIME::Color[outFmt]||0)  # format -> color

        env[:mapped].
          sort_by{|k, stat| stat[:count]}.reverse.
          map{|k, stat| puts [stat[:count], k, stat[:target]].join "\t"} if debug?

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
