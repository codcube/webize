%w(async async/barrier async/semaphore brotli cgi digest/sha2 open-uri rack resolv).map{|_| require _}

class WebResource
  module HTTP
    include URIs
    Args = Webize.configList 'HTTP/arguments'            # permitted query arguments
    Methods = Webize.configList 'HTTP/methods'           # permitted HTTP methods
    HostGET = {}                                         # handler-lambda storage
    PeerHosts = Hash[*File.open([ENV['PREFIX'],'/etc/hosts'].join).readlines.map(&:chomp).map{|l|
                       addr, *names = l.split
                       names.map{|host|
                         [host, addr]}}.flatten]         # peer host -> peer addr map
    PeerAddrs = PeerHosts.invert                         # peer addr -> peer host map
    LocalAddrs = Socket.ip_address_list.map &:ip_address # local addresses
    ActionIcon = Webize.configHash 'style/icons/action'  # HTTP method -> character
    StatusIcon = Webize.configHash 'style/icons/status'  # status code -> character

    def self.bwPrint kv; kv.map{|k,v| "\e[38;5;7;7m#{k}\e[0m#{v}" } end

    # Rack entry-point
    def self.call env
      return [403,{},[]] unless Methods.member? env['REQUEST_METHOD']

      env[:start_time] = Time.now                           # start timer
      env['SERVER_NAME'].downcase!                          # normalize hostname
      env.update HTTP.env                                   # storage fields

      isPeer = PeerHosts.has_key? env['SERVER_NAME']        # peer node?
      isLocal = LocalAddrs.member?(PeerHosts[env['SERVER_NAME']] || env['SERVER_NAME']) # local node?

      uri = (isLocal ? '/' : [isPeer ? :http : :https,'://',# scheme if non-local
                              env['HTTP_HOST']].join).R.join(RDF::URI(env['REQUEST_PATH']).path).R env
      uri.port = nil if [80,443,8000].member? uri.port      # port if non-default
      if env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # query if non-empty
        env[:qs] = ('?' + env['QUERY_STRING'].sub(/^&+/,'').sub(/&+$/,'').gsub(/&&+/,'&')).R.query_values || {} # strip excess &s to not trip up URI libraries
        qs = env[:qs].dup                                   # full query - proxy and origin args - parsed and memoized
        Args.map{|k|                                        # (💻 <> 🖥) argnames
         env[k.to_sym]=qs.delete(k)||true if qs.has_key? k} # (💻 <> 🖥) args for request in environment
        uri.query_values = qs unless qs.empty?              # (🖥 <> ☁️) args for follow-on requests in URI
      end

      env[:base] = uri.to_s.R env                           # base URI
      env[:client_tags] = env['HTTP_IF_NONE_MATCH'].strip.split /\s*,\s*/ if env['HTTP_IF_NONE_MATCH'] # parse etags
      env[:proxy_href] = isPeer || isLocal                  # relocate hrefs?

      URIs.blocklist if env['HTTP_CACHE_CONTROL']=='no-cache' # refresh blocklist on force-reload (browser ctrl-shift-R)

      uri.send(env['REQUEST_METHOD']).yield_self{|status, head, body|
        sp = '  '                                                    # spacer
        format = uri.format_icon(head['Content-Type']) || sp         # format icon
        color = env[:deny] ? '38;5;196' : (FormatColor[format] || 0) # format color
        log [(env[:base].scheme == 'http' && !isPeer) ? '🔓' : nil,  # protocol security
             if env[:deny]                                           # action
               '🛑'
             elsif StatusIcon.has_key? status
               StatusIcon[status]
             elsif ActionIcon.has_key? env['REQUEST_METHOD']
               ActionIcon[env['REQUEST_METHOD']]
             elsif uri.offline?
               '🔌'
             else
               sp
             end,
             format,                                                              # format
             env[:fetched] ? (ENV.has_key?('http_proxy') ? '🖥' : '🐕') : sp,      # fetch type
             uri.format_icon(env[:origin_format]) || sp,                          # upstream/origin format
             (env[:repository]&.size).to_s.rjust(4), '⋮ ',                        # graph size
             env['HTTP_REFERER'] ? ["\e[#{color}m",env['HTTP_REFERER'].R.display_host,"\e[0m → "] : nil, # referer
             "\e[#{color}#{env[:base].host && env['HTTP_REFERER'] && !env['HTTP_REFERER'].index(env[:base].host) && ';7' || ''}m", # invert off-site referer
             env[:base].host && env[:base].display_host, env[:base].path, "\e[0m",# path
             (qs.map{|k,v|"\e[38;5;7;7m#{k}\e[0m#{v} "} if qs && !qs.empty?),     # query
             head['Location'] ? ["→\e[#{color}m",head['Location'],"\e[0m"] : nil, # location
             env[:warning] ? ["\e[38;5;226;7m⚠️", env[:warning], "\e[0m"] : nil,   # warning
            ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join
        [status, head, body]}                                                     # response
    rescue Exception => e
      Console.logger.failure uri, e
      [500, {'Content-Type' => 'text/html; charset=utf-8'},
       uri.head? ? [] : ["<html><body class='error'>#{HTML.render [{_: :style, c: Webize::CSS::SiteCSS}, {_: :script, c: Webize::Code::SiteJS}, uri.uri_toolbar]}500</body></html>"]]
    end

    def cookieCache
      cookie = join('/cookie').R                      # cookie-jar URI
      if env[:cookie] && !env[:cookie].empty?         # store cookie to jar
        cookie.writeFile env[:cookie]
         logger.info [:🍯, host, env[:cookie]].join ' '
      end
      if cookie.file?                                 # read cookie from jar
        env['HTTP_COOKIE'] = cookie.node.read
        logger.info [:🍪, host, env['HTTP_COOKIE']].join ' '
      end
    end

    def HTTP.decompress head, body
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
      logger.failure head, e
      head['Content-Encoding'] = encoding
      body
    end

    # initialize environment storage
    def HTTP.env
      {client_etags: [],
       feeds: [],
       links: {},
       qs: {}}
    end

    def env e = nil
      if e
        @env = e
        self
      else
        @env ||= {}
      end
    end

    # fetch node(s) from local or remote host
    def fetch nodes = nil
      return fetchLocal nodes if offline?                   # offline cache
      if file?                                              # cached file?
        return fileResponse if fileMIME.match?(FixedFormat) && !basename.match?(/index/i) # immutable nodes are always up-to-date
        env[:cache] = self                                  # cache reference for conditional fetch
      elsif directory? && (🐢 = join('index.ttl').R).exist? # cached dir-index?
        env[:cache] = 🐢                                    # cache reference for conditional fetch
      end
      if nodes # fetch node(s)
        barrier = Async::Barrier.new
	semaphore = Async::Semaphore.new(16, parent: barrier)
        nodes.map{|n|
          semaphore.async do
            n.fetchRemote
            print :🐕
          end}
        barrier.wait
        r.saveRDF.graphResponse
      else # fetch node
        # name may resolve to localhost. define hostname in HOSTS to get a path-only URI in #call and not reach this lookup
        env[:addr] = Resolv.getaddress host rescue '127.0.0.1'
        (LocalAddrs.member? env[:addr]) ? fetchLocal : fetchRemote
      end
    end

    # fetch node to graph and cache
    def fetchHTTP format: nil, thru: true                   # options: MIME (override erroneous origin), HTTP response for caller
      head = headers.merge({redirect: false})               # parse client headers, disable automagic/hidden redirect following
      unless env[:notransform]                              # query ?notransform for upstream UI on content-negotiating servers
        head['Accept'] = ['text/turtle', head['Accept']].join ',' unless head['Accept']&.match? /text\/turtle/ # accept 🐢/turtle
      end
      head['If-Modified-Since'] = env[:cache].mtime.httpdate if env[:cache] # timestamp for conditional fetch

      #logger.debug ["\e[7m🖥 → ☁️  #{uri}\e[0m ", HTTP.bwPrint(head)].join # request headers

      URI.open(uri, head) do |response|                     # HTTP(S) fetch
        h = headers response.meta                           # response metadata

        #logger.debug ["\e[7m🥩 ← ☁️ \e[0m ", HTTP.bwPrint(response.meta)].join # raw upstream headers
        #logger.debug ["\e[7m🧽 ← ☁️ \e[0m ", HTTP.bwPrint(h)].join # cleaned upstream headers

        env[:origin_status] = response.status[0].to_i       # response status
        case env[:origin_status]
        when 204                                            # no content
          [204, {}, []]
        when 206                                            # partial content
          h['Access-Control-Allow-Origin'] ||= origin
          [206, h, [response.read]]
        else                                                # full content
          body = HTTP.decompress h, response.read           # decompress content
          format ||= if path == '/feed'                     # format fixed on remote /feed due to erroneous upstream text/html headers
                       'application/atom+xml'
                     elsif content_type = h['Content-Type'] # format defined in HTTP header
                       ct = content_type.split(/;/)
                       if ct.size == 2 && ct[1].index('charset') # charset defined in HTTP header
                         charset = ct[1].sub(/.*charset=/i,'')
                         charset = nil if charset.empty? || charset == 'empty'
                       end
                       ct[0]
                     end
          if format                                         # format defined
            format.downcase!                                # normalize case
            if !charset && format.index('html') && metatag = body[0..4096].encode('UTF-8', undef: :replace, invalid: :replace).match(/<meta[^>]+charset=['"]?([^'">]+)/i)
              charset = metatag[1]                          # charset defined in document header
            end
            if charset                                      # charset defined?
              charset = 'UTF-8' if charset.match? /utf.?8/i # normalize UTF-8 charset symbols
              charset = 'Shift_JIS' if charset.match? /s(hift)?.?jis/i # normalize Shift-JIS charset symbols
              unless Encoding.name_list.member? charset     # ensure charset is in encoding set
                logger.warn "⚠️ unsupported charset #{charset} in #{uri}"
                charset = 'UTF-8'                           # default charset
              end
            end
            if format.match? /(ht|x)ml|script|text/         # encode text formats in UTF-8
              body.encode! 'UTF-8', charset || 'UTF-8', invalid: :replace, undef: :replace
            end
            if format == 'application/xml' && body[0..2048].match?(/(<|DOCTYPE )html/i)
              format = 'text/html'                          # HTML served w/ XML MIME
            end
            env[:origin_format] = format                    # upstream format
            fixed_format = format.match? FixedFormat        # fixed format?

            body = Webize.clean self, body, format          # clean upstream data

            file = fsPath                                   # cache storage
            if file[-1] == '/'                              # container
              file += 'index'
            elsif directory?                                # container sans '/'
              file += '/index'
            end
            POSIX.container file                            # create container(s)
            ext = (File.extname(file)[1..-1] || '').to_sym  # upstream suffix
            if (formats = RDF::Format.content_types[format]) && # content-type
               (extensions = formats.map(&:file_extension).flatten) && # suffixes for content-type
               !extensions.member?(ext)                     # suffix not mapped to content-type
              file = [(link = file),'.',extensions[0]].join # append suffix
              FileUtils.ln_s File.basename(file), link unless File.basename(link) == 'index' # link path
            end
            File.open(file, 'w'){|f| f << body }            # cache static entity

            if timestamp = h['Last-Modified']               # HTTP provided timestamp
              timestamp.sub! /((ne|r)?s|ur)?day/, ''        # strip day name to 3-letter abbr
              if t = Time.httpdate(timestamp) rescue nil    # parse timestamp
                FileUtils.touch file, mtime: t              # cache timestamp
              else
                logger.warn ['⚠️  malformed datetime:', h['Last-Modified'], timestamp != h['Last-Modified'] ? [:→, timestamp] : nil].join ' '
              end
            end

            if reader = RDF::Reader.for(content_type: format) # reader defined for format?
              env[:repository] ||= RDF::Repository.new      # initialize RDF repository
              env[:repository] << RDF::Statement.new(self, Date.R, t.iso8601) if t
              case format
              when /image/
                env[:repository] << RDF::Statement.new(self, Type.R, Image.R)
              when /video/
                env[:repository] << RDF::Statement.new(self, Type.R, Video.R)
              end
              reader.new(body, base_uri: self, path: file){|g|env[:repository] << g} # read RDF
              if format == 'text/html' && reader != RDF::RDFa::Reader                # read RDFa
                RDF::RDFa::Reader.new(body, base_uri: self){|g|
                  g.each_statement{|statement|
                    if predicate = Webize::MetaMap[statement.predicate.to_s]
                      next if predicate == :drop
                      statement.predicate = predicate.R
                    end
                    env[:repository] << statement }} rescue logger.warn("⚠️ RDFa::Reader failed")
              end
            else
              logger.warn "⚠️ Reader undefined for #{format}"
            end unless format.match?(/octet-stream/) || body.empty?
          else
            logger.warn "⚠️ format undefined on #{uri}"
          end

          return unless thru                                # HTTP response for caller?
          saveRDF                                           # update graph-cache

          h['Link'] && h['Link'].split(',').map{|link|      # parse upstream Link headers
            ref, type = link.split(';').map &:strip
            if ref && type
              ref = ref.sub(/^</,'').sub />$/, ''
              type = type.sub(/^rel="?/,'').sub /"$/, ''
              env[:links][type.to_sym] = ref
            end}
          if h['Set-Cookie'] && CookieHosts.member?(host) && !(cookie = env[:base].join('/cookie').R).exist?
            cookie.writeFile h['Set-Cookie']                # update cookie-cache
            logger.info [:🍯, host, h['Set-Cookie']].join ' '
          end

          if env[:client_etags].include? h['ETag']          # client has entity
            [304, {}, []]                                   # no content
          elsif env[:notransform] || fixed_format           # static content
            body = Webize::HTML.resolve_hrefs body, env, true if format == 'text/html' && env[:proxy_href] # resolve proxy-hrefs
            head = {'Content-Type' => format,               # response header
                    'Content-Length' => body.bytesize.to_s}
            %w(ETag Last-Modified).map{|k|head[k] = h[k] if h[k]} # upstream headers for caller
            head['Expires']=(Time.now+3e7).httpdate if fixed_format # cache static assets
            [200, head, [body]]                             # response in upstream format
          else                                              # content-negotiated transform
            graphResponse format                            # response in preferred format
          end
        end
      end
    rescue Exception => e                                   # response codes mapped to exceptions by HTTP library
      raise unless e.respond_to?(:io) && e.io.respond_to?(:status)
      status = e.io.status[0].to_i                          # response status
      case status.to_s
      when /30[12378]/                                      # redirected
        location = e.io.meta['location']
        dest = join(location).R env
        if no_scheme == dest.no_scheme                      # alternate scheme
          if scheme == 'https' && dest.scheme == 'http'     # downgrade
            logger.warn "⚠️  downgrade redirect #{dest}"
            dest.fetchHTTP
          elsif scheme == 'http' && dest.scheme == 'https'  # upgrade
            logger.debug "🔒 upgrade redirect #{dest}"
            dest.fetchHTTP
          else                                              # redirect loop
            logger.warn "discarding #{uri} → #{location} redirect"
            fetchLocal
          end
        else
          [status, {'Location' => dest.href}, []]
        end
      when /304/                                            # origin unmodified
        fetchLocal
      when /300|[45]\d\d/                                   # not allowed/available/found
        env[:origin_status] = status
        head = headers e.io.meta
        body = HTTP.decompress(head, e.io.read).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        if head['Content-Type']&.index 'html'
          body = Webize::HTML.clean body, self
          env[:repository] ||= RDF::Repository.new
          RDF::Reader.for(content_type: 'text/html').new(body, base_uri: self){|g|env[:repository] << g} # read origin RDF
        end
        head['Content-Length'] = body.bytesize.to_s
        env[:notransform] ? [status, head, [body]] : env[:base].fetchLocal # origin or cache response
      else
        raise
      end
    end

    def fetchLocal nodes = nil
      return fileResponse if !nodes && file? && (format = fileMIME) && # file if cached and one of:
                             (env[:notransform] ||          # (mimeA → mimeB) transform disabled
                              format.match?(FixedFormat) || # (mimeA → mimeB) transform unimplemented
                              (format==selectFormat(format) && !ReFormat.member?(format))) # (mimeA) reformat disabled
      (nodes || fsNodes).map &:loadRDF                      # load node(s)
      dirMeta                                               # 👉 storage-adjacent nodes
      timeMeta unless host                                  # 👉 timeline-adjacent nodes
      graphResponse                                         # response
    end

    def fetchRemote
      env[:fetched] = true                                  # denote network-fetch for logger
      case scheme                                           # request scheme
      when 'gemini'
        fetchGemini                                         # fetch w/ Gemini
      when 'http'
        fetchHTTP                                           # fetch w/ HTTP
      when 'https'
        if ENV.has_key?('http_proxy')
          insecure.fetchHTTP                                # fetch w/ HTTP from private-network proxy
        elsif PeerAddrs.has_key? env[:addr]
          url = insecure; url.port = 8000; url.fetchHTTP    # fetch w/ HTTP from private-network peer
        else
          fetchHTTP                                         # fetch w/ HTTPS from origin
        end
      when 'spartan'                                        # fetch w/ Spartan
        fetchSpartan
      else
        logger.warn "⚠️ unsupported scheme #{uri}"; notfound # unsupported scheme
      end
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError, OpenSSL::SSL::SSLError, RuntimeError, SocketError => e
      env[:warning] = [e.class, e.message].join ' '         # warn on error/fallback condition
      if scheme == 'https'                                  # HTTPS failure?
        insecure.fetchHTTP rescue notfound                  # fallback to HTTP
      else
        notfound
      end
    end

    def self.GET arg, lambda = -> r {r.send r.uri.match?(Gunk) ? :deny : :fetch}
      HostGET[arg] = lambda
    end

    def GET
      return hostHandler if host                 # remote node - canonical URI
      p = parts[0]                               # path selector
      return fetchLocal unless p                 # root local node
      return unproxy.hostHandler if p[-1] == ':' # remote node - proxy URI
      return icon if p == 'favicon.ico'          # icon served from RAM
      return unproxy.hostHandler if p.index '.'  # remote node - proxy URI
      return dateDir if %w{m d h y}.member? p    # current year/month/day/hour container
      return inbox if p == 'mailto'              # inbox redirect
      fetchLocal                                 # local node
    end

    def has_handler?; HostGET.has_key? host.downcase end

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # header and status
    end

    def head?; env['REQUEST_METHOD'] == 'HEAD' end

    # client<>proxy connection-specific/server-internal headers - not relevant to proxy<>origin connection
    SingleHopHeaders = %w(async.http.request connection host if-modified-since if-none-match keep-alive path-info query-string
 remote-addr request-method request-path request-uri script-name server-name server-port server-protocol server-software
 te transfer-encoding unicorn.socket upgrade upgrade-insecure-requests version via x-forwarded-for)

    # recreate headers from their mangled CGI keynames
    # PRs pending for rack/falcon, maybe we can finally remove this soon
    def headers raw = nil
      raw ||= env || {}                               # raw headers
      head = {}                                       # cleaned headers
      raw.map{|k,v|                                   # inspect (k,v) pairs
        unless k.class!=String || k.index('rack.')==0 # skip internal headers
          key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip prefix and tokenize
            if %w{cf cl csrf ct dfe dnt id spf utc xss xsrf}.member? t
              t.upcase                                # upcase acronym
            elsif 'etag' == t
              'ETag'                                  # partial acronym
            else
              t.capitalize                            # capitalize word
            end}.join '-'                             # join words
          head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless SingleHopHeaders.member? key.downcase # set header
        end}


      head['Referer'] = 'http://drudgereport.com/' if host&.match? /wsj\.com$/ # referer tweaks so stuff loads
      head['Referer'] = 'https://' + (host || env['HTTP_HOST']) + '/' if (path && %w(.gif .jpeg .jpg .png .svg .webp).member?(File.extname(path).downcase)) || parts.member?('embed')

      head['User-Agent'] = 'curl/7.82.0' if %w(po.st t.co).member? host # to prefer HTTP HEAD redirections e over procedural Javascript, advertise a basic user-agent
      head
    end

    def hostHandler
      qs = query_values || {}                         # parse query
      dirMeta                                         # add directory metadata
      cookieCache                                     # load/save cookies
      return [204, {}, []] if parts[-1]&.match? /^(gen(erate)?|log)_?204$/ # "connectivity check" 204 response
      return ENV.has_key?('http_proxy') ? fetch : HostGET[host.downcase][self] if has_handler? # host adaptor if origin-facing (no intermediary proxy)
      return [301,{'Location' => ['//', host, path].join.R(env).href},[]] if query&.match? Gunk # drop gunked-up query
      return fetch if host.match?(CDNhost) && (!path || uri.match?(CDNdoc)) # allow CDN content
      deny? ? deny : fetch                            # generic remote node
    end

    def icon
      [200,
       {'Content-Type' => 'image/png',
        'Expires' => (Time.now + 86400).httpdate}, [WebResource::HTML::SiteIcon]]
    end

    def inbox # redirect from email-address URI to current month's mailbox
      [302,
       {'Location' => ['/m/',                                                            # current month (change to day if heavy email user)
                       (parts[1].split(/[\W_]/) - BasicSlugs).map(&:downcase).join('.'), # address slug
                       '?view=table&sort=date'].join}, []]
    end

    def linkHeader
      return unless env.has_key? :links
      env[:links].map{|type,uri|
        "<#{uri}>; rel=#{type}"}.join(', ')
    end

    def notfound
      format = selectFormat
      body = case format
             when /html/                                              # serialize HTML
               htmlDocument treeFromGraph.update({'#request' => env}) # show environment
             when /atom|rss|xml/
               feedDocument treeFromGraph                             # serialize Atom/RSS
             else
               if env[:repository] && writer = RDF::Writer.for(content_type: format)
                 env[:repository].dump writer.to_sym, base_uri: self  # serialize RDF
               end
             end
      [404, {'Content-Type' => format}, head? ? nil : [body ? body : '']]
    end

    def offline?
      ENV.has_key? 'OFFLINE'
    end

    def origin
      if env['HTTP_ORIGIN']
        env['HTTP_ORIGIN']
      elsif referer = env['HTTP_REFERER']
        'http' + (host == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
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

  include HTTP

end
