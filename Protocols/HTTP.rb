%w(async async/barrier async/semaphore brotli cgi digest/sha2 open-uri rack resolv).map{|_| require _}

class WebResource
  module HTTP
    include URIs
    Args = Webize.configList 'HTTP/arguments'            # permitted query arguments
    Methods = Webize.configList 'HTTP/methods'           # permitted HTTP methods
    HostGET = {}; Subscriptions = {}                     # host handler and subscription-list storage
    PeerHosts = Hash[*File.open([ENV['PREFIX'],'/etc/hosts'].join).readlines.map(&:chomp).map{|l|
                       addr, *names = l.split
                       names.map{|host|
                         [host, addr]}}.flatten]         # peer host -> peer addr map
    PeerAddrs = PeerHosts.invert                         # peer addr -> peer host map
    LocalAddrs = Socket.ip_address_list.map &:ip_address # local addresses
    ActionIcon = Webize.configHash 'style/icons/action'  # HTTP method -> char
    StatusIcon = Webize.configHash 'style/icons/status'  # status code (string) -> char
    StatusIcon.keys.map{|s|                              # status code (int) -> char
      StatusIcon[s.to_i] = StatusIcon[s]}

    def self.bwPrint kv; kv.map{|k,v| "\e[38;5;7;7m#{k}\e[0m#{v}" } end

    # Rack entry-point
    def self.call env
      return [403,{},[]] unless Methods.member? env['REQUEST_METHOD']

      env[:start_time] = Time.now                           # start timer
      env['SERVER_NAME'].downcase!                          # normalize hostname
      env.update HTTP.env                                   # init environment storage

      isPeer = PeerHosts.has_key? env['SERVER_NAME']        # peer node?
      isLocal = LocalAddrs.member?(PeerHosts[env['SERVER_NAME']] || env['SERVER_NAME']) # local node?

      uri = (isLocal ? '/' : [isPeer ? :http : :https,'://',# scheme if non-local
                              env['HTTP_HOST']].join).R.join(RDF::URI(env['REQUEST_PATH']).path).R env
      uri.port = nil if [80,443,8000].member? uri.port      # port if non-default
      if env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # query if non-empty
        env[:qs] = ('?' + env['QUERY_STRING'].sub(/^&+/,'').sub(/&+$/,'').gsub(/&&+/,'&')).R.query_values || {} # strip excess & and parse
        qs = env[:qs].dup                                   # parsed query from caller
        Args.map{|k|                                        # (💻 <> 🖥) local argument names
         env[k.to_sym]=qs.delete(k)||true if qs.has_key? k} # (💻 <> 🖥) args for request in environment
        uri.query_values = qs unless qs.empty?              # (🖥 <> ☁️) args for follow-on requests in URI
      end

      env[:base] = uri.to_s.R env                           # base URI
      env[:client_tags] = env['HTTP_IF_NONE_MATCH'].strip.split /\s*,\s*/ if env['HTTP_IF_NONE_MATCH'] # parse etags
      env[:proxy_href] = isPeer || isLocal                  # relocate hrefs?

      URIs.blocklist if env['HTTP_CACHE_CONTROL']=='no-cache' # refresh blocklist on force-reload (browser ctrl-shift-R)

      uri.send(env['REQUEST_METHOD']).yield_self{|status,head,body| # call request and inspect response
        inFmt = uri.format_icon env[:origin_format]                 # input format
        outFmt = uri.format_icon head['Content-Type']               # output format
        color = env[:deny] ? '38;5;196' : (FormatColor[outFmt]||0)  # format -> color
        referer = env['HTTP_REFERER'].R if env['HTTP_REFERER']      # referer

        log [(env[:base].scheme == 'http' && !isPeer) ? '🔓' : nil, # transport security
             if env[:deny]                                          # action taken:
               '🛑'                                                 # blocked
             elsif StatusIcon.has_key? status
               StatusIcon[status]                                   # status code
             elsif ActionIcon.has_key? env['REQUEST_METHOD']
               ActionIcon[env['REQUEST_METHOD']]                    # HTTP method
             elsif uri.offline?
               '🔌'                                                 # offline response
             end,
             (ENV.has_key?('http_proxy') ? '🖥' : '🐕' if env[:fetched]), # upstream type: origin or middlebox
             ([(env[:updates] || env[:repository]).size, '⋮'] if env[:repository] && env[:repository].size > 0), ' ', # graph size
             referer ? ["\e[#{color}m", referer.display_host, "\e[0m → "] : nil, # referer
             outFmt, ' ',                                           # output format
             "\e[#{color}#{';7' if referer && referer.host != env[:base].host}m", # invert off-site referer
             (env[:base].display_host unless referer && referer.host == env[:base].host), env[:base].path, "\e[0m", # host, path
             ([' ⟵ ', inFmt, ' '] if inFmt && inFmt != outFmt),     # input format, if transcoded
             (qs.map{|k,v|" \e[38;5;7;7m#{k}\e[0m #{v}"} if qs && !qs.empty?), # query
             head['Location'] ? [" → \e[#{color}m", head['Location'].R.unproxyURI, "\e[0m"] : nil, # redirected location
             env[:warning] ? [" \e[38;5;226m⚠️", env[:warning], "\e[0m"] : nil, # warning
            ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join

        [status, head, body]}                                       # response
    rescue Exception => e
      Console.logger.failure uri, e
      [500, {'Content-Type' => 'text/html; charset=utf-8'},
       uri.head? ? [] : ["<html><body class='error'>#{HTML.render [{_: :style, c: Webize::CSS::SiteCSS}, {_: :script, c: Webize::Code::SiteJS}, uri.uri_toolbar]}500</body></html>"]]
    end

    # site adaptation runs on last proxy in chain
    def adapt?
      !ENV.has_key?('http_proxy')
    end

    def block domain
      File.open([Webize::ConfigPath, :blocklist, :domain].join('/'), 'a'){|list|
        list << domain << "\n"} # add to blocklist
      URIs.blocklist            # read blocklist
      [302, {'Location' => ['//', domain].join.R(env).href}, []]
    end

    def cookieCache
      cookie = join('/cookie').R                      # jar
      if env[:cookie] && !env[:cookie].empty?         # store cookie to jar
        cookie.writeFile env[:cookie]
        logger.info [:🍯, host, env[:cookie]].join ' '
      end
      if cookie.file?                                 # load cookie from jar
        env['HTTP_COOKIE'] = cookie.node.read
        logger.debug [:🍪, host, env['HTTP_COOKIE']].join ' '
      end
      # host-specific token wrangling
      case host
      when 'gitter.im'
        gitterAuth
      when 'twitter.com'
        twAuth
      end
    end

    def debug?
      ENV['CONSOLE_LEVEL'] == 'debug'
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
      Console.logger.failure head, e
      head['Content-Encoding'] = encoding
      body
    end

    def deny status = 200, type = nil
      env[:deny] = true
      return [301,{'Location' => ['//', host, path].join.R(env).href},[]] if query&.match? Gunk # drop query
      ext = File.extname basename if path
      type, content = if type == :stylesheet || ext == '.css'
                        ['text/css', '']
                      elsif type == :font || %w(.eot .otf .ttf .woff .woff2).member?(ext)
                        ['font/woff2', WebResource::HTML::SiteFont]
                      elsif type == :image || %w(.bmp .ico .gif .jpg .png).member?(ext)
                        ['image/png', WebResource::HTML::SiteIcon]
                      elsif type == :script || ext == '.js'
                        ['application/javascript', "// URI: #{uri.match(Gunk) || host}"]
                      elsif type == :JSON || ext == '.json'
                        ['application/json','{}']
                      else
                        env.delete :view
                        env[:qs].map{|k,v|
                          env[:qs][k] = v.R if v && v.index('http')==0 && !v.index(' ')}
                        ['text/html; charset=utf-8', htmlDocument({'#req'=>env})]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => origin,
        'Content-Type' => type},
       head? ? [] : [content]]
    end

    def dropQS
      if !query                         # URL is query-free
        fetch.yield_self{|s,h,b|        # call origin
          h.keys.map{|k|                # strip redirected-location query
            if k.downcase == 'location' && h[k].match?(/\?/)
              Console.logger.info "dropping query from #{h[k]}"
              h[k] = h[k].split('?')[0]
            end
          }
          [s,h,b]}                        # response
      else                                # redirect to no-query location
        Console.logger.info "dropping query from #{uri}"
        [302, {'Location' => ['//', host, path].join.R(env).href}, []]
      end
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
    def fetch nodes=nil, **opts
      return fetchLocal nodes if offline? # return offline cache
      if file?                            # cached node?
        return fileResponse if fileMIME.match?(FixedFormat) && !basename.match?(/index/i) # return immutable node
        cache = self                      # cache reference
      elsif directory? && (🐢 = join('index.🐢').R env).exist? # cached directory index?
        cache = 🐢                        # cache reference
        cache.loadRDF
      end
      env['HTTP_IF_MODIFIED_SINCE'] = cache.mtime.httpdate if cache # timestamp for conditional fetch

      if nodes # fetch node(s) asynchronously
        env[:updates] = RDF::Repository.new # initialize updates graph
        opts[:thru] = false
        barrier = Async::Barrier.new
	semaphore = Async::Semaphore.new(16, parent: barrier)
        nodes.map{|n|
          semaphore.async do
            print format_icon n.R(env).fetchRemote **opts
          end}
        barrier.wait
        graphResponse
      else # fetch node
        # name may resolve to localhost. define hostname in HOSTS to get a path-only URI in #call and not reach this lookup
        env[:addr] = Resolv.getaddress host rescue '127.0.0.1'
        (LocalAddrs.member? env[:addr]) ? fetchLocal : fetchRemote
      end
    end

    def fetchHTTP thru: true                                # option: return HTTP response through to caller?
      URI.open(uri, headers.merge({redirect: false})) do |response|
        h = headers response.meta                           # response headera
        case env[:origin_status] = response.status[0].to_i  # response status
        when 204                                            # no content
          [204, {}, []]
        when 206                                            # partial content
          h['Access-Control-Allow-Origin'] ||= origin
          [206, h, [response.read]]
        else                                                # massage metadata, cache and return data
          body = HTTP.decompress h, response.read           # decompress body
          if format = if path == '/feed'                    # format override on remote /feed due to common upstream text/html or text/plain headers
                        'application/atom+xml'
                      elsif content_type = h['Content-Type'] # format defined in HTTP header
                        ct = content_type.split(/;/)
                        if ct.size == 2 && ct[1].index('charset') # charset defined in HTTP header
                          charset = ct[1].sub(/.*charset=/i,'')
                          charset = nil if charset.empty? || charset == 'empty'
                        end
                        ct[0]
                      end
            env[:repository] ||= RDF::Repository.new        # request graph
            env[:origin_format] = format                    # original format
            format.downcase!                                # normalize format
            if !charset && format.index('html') && metatag = body[0..4096].encode('UTF-8', undef: :replace, invalid: :replace).match(/<meta[^>]+charset=['"]?([^'">]+)/i)
              charset = metatag[1]                          # charset defined in-band in content
            end
            charset = charset ? (normalize_charset charset) : 'UTF-8'     # normalize charset
            body.encode! 'UTF-8', charset, invalid: :replace, undef: :replace if format.match? /(ht|x)ml|script|text/ # encode in UTF-8
            format = 'text/html' if format == 'application/xml' && body[0..2048].match?(/(<|DOCTYPE )html/i) # HTML served as XML
            static = env[:notransform] || format.match?(FixedFormat)      # transformable content?
            doc = document                                                # cache location
            if (formats = RDF::Format.content_types[format]) &&           # content type
               (extensions = formats.map(&:file_extension).flatten) &&    # name suffix(es) for content type
               !extensions.member?((File.extname(doc)[1..-1]||'').to_sym) # upstream suffix maps to content-type?
              doc = [(link = doc), '.', extensions[0]].join               # append valid MIME suffix
              FileUtils.ln_s File.basename(doc), link                     # link corrected name to canonical name
            end
            File.open(doc, 'w'){|f| f << body }                           # update cache content
            if timestamp = h['Last-Modified']                             # HTTP metadata timestamp
              if t = Time.httpdate(timestamp) rescue nil                  # parse timestamp
                FileUtils.touch doc, mtime: t                             # update cache timestamp
                env[:repository] << RDF::Statement.new(self, Date.R, t.iso8601) # emit timestamp to request graph
              end
            end
            readRDF format, body, env[:repository]                        # read fetched data into request graph
          end
          return format unless thru                                       # return HTTP response to caller?
          static ? (staticResponse format, body) : (graphResponse format) # response in content-negotiated format
        end
      end
    rescue Exception => e
      raise unless e.respond_to?(:io) && e.io.respond_to?(:status)
      status = e.io.status[0].to_i                          # status raised to exception by HTTP library
      case status.to_s
      when /30[12378]/                                      # redirect
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
            logger.warn "🛑 redirect loop → #{location}"
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
                             (env[:notransform] ||          # (mimeA → mimeB) transform disabled (client preference)
                              format.match?(FixedFormat) || # (mimeA → mimeB) transform disabled or unimplemented (server preference)
                              (format == selectFormat(format) && !ReFormat.member?(format))) # (mimeA) reformat disabled
      (nodes || fsNodes).map &:loadRDF                      # load node(s)
      dirMeta                                               # 👉 storage-adjacent nodes
      timeMeta unless host                                  # 👉 timeline-adjacent nodes
      graphResponse                                         # response
    end

    def fetchRemote **opts
      env[:fetched] = true                                  # denote network-fetch for logger
      case scheme                                           # request scheme
      when 'gemini'
        fetchGemini                                         # fetch w/ Gemini
      when 'http'
        fetchHTTP **opts                                    # fetch w/ HTTP
      when 'https'
        if ENV.has_key?('http_proxy')
          insecure.fetchHTTP **opts                         # fetch w/ HTTP from proxy
        elsif PeerAddrs.has_key? env[:addr]
          url = insecure
          url.port = 8000
          url.fetchHTTP **opts                              # fetch w/ HTTP from peer
        else
          fetchHTTP **opts                                  # fetch w/ HTTPS
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

    # define a host-specific GET handler
    def self.GET arg, lambda = -> r {r.send r.uri.match?(Gunk) ? :deny : :fetch}
      HostGET[arg] = lambda
    end

    Webize.configList('hosts/shorturl').map{|h|GET h, -> r {r.dropQS}}

    Webize.configList('hosts/url').map{|h|
      GET h, -> r {
        q = r.query_values || {}
        dest = q['url'] || q['u'] || q['q']
        dest ? [301, {'Location' => dest.R(r.env).href}, []] : r.notfound}}

    def GET
      return hostGET if host                  # remote node at canonical URI
      p = parts[0]                            # path selector
      return fetchLocal unless p              # root local node
      return unproxy.hostGET if p[-1] == ':'  # remote node at proxy URI w/ scheme
      return icon if p == 'favicon.ico'       # icon
      return unproxy.hostGET if p.index '.'   # remote node at proxy URI w/o scheme
      return dateDir if %w{m d h y}.member? p # current year/month/day/hour's container
      return inbox if p == 'mailto'           # inbox redirect
      return block parts[1] if p == 'block'   # block site
      fetchLocal                              # local node
    end

    def graphResponse defaultFormat = 'text/html'
      saveRDF if host                                 # cache remote graph
      if !env.has_key?(:repository) || env[:repository].empty? # no graph data
        return notfound
      end

      status = env[:origin_status] || 200             # response status
      format = selectFormat defaultFormat             # response format
      format += '; charset=utf-8' if %w{text/html text/turtle}.member? format
      head = {'Access-Control-Allow-Origin' => origin,# response header
              'Content-Type' => format,
              'Last-Modified' => Time.now.httpdate,
              'Link' => linkHeader}
      return [status, head, nil] if head?             # header-only response

      body = case format                              # response body
             when /html/
               htmlDocument treeFromGraph             # serialize HTML
             when /atom|rss|xml/
               feedDocument treeFromGraph             # serialize Atom/RSS
             else                                     # serialize RDF
               if writer = RDF::Writer.for(content_type: format)
                 env[:repository].dump writer.to_sym, base_uri: self
               else
                 logger.warn "⚠️  RDF::Writer undefined for #{format}" ; ''
               end
             end

      head['Content-Length'] = body.bytesize.to_s     # response size
      [status, head, [body]]                          # response
    end

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # header and status
    end

    def head?; env['REQUEST_METHOD'] == 'HEAD' end

    # client<>proxy connection-specific/server-internal headers - not relevant to proxy<>origin connection
    SingleHopHeaders = Webize.configTokens 'blocklist/header'

    # recreate headers from their mangled CGI keynames
    # PRs pending for rack/falcon, maybe we can finally remove this soon
    def headers raw = nil
      raw ||= env || {}                               # raw headers
      head = {}                                       # cleaned headers
      logger.debug ["\e[7m🥩 ← 🗣 \e[0m ", HTTP.bwPrint(raw)].join if debug? # raw debug-prints

      raw.map{|k,v|                                   # (key, val) tuples
        unless k.class!=String || k.match?(/^(protocol|rack)\./i) # except rack/server-use fields
          key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip HTTP prefix and split tokens
            if %w{cf cl csrf ct dfe dnt id spf utc xss xsrf}.member? t
              t.upcase                                # upcase acronym
            elsif 'etag' == t
              'ETag'                                  # partial acronym
            else
              t.capitalize                            # capitalize word
            end}.join '-'                             # join words
          head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless SingleHopHeaders.member? key.downcase # set header
        end}

      head['Accept'] = ['text/turtle', head['Accept']].join ',' unless env[:notransform] || head['Accept']&.match?(/text\/turtle/) # accept 🐢/turtle. add ?notransform to base URI to disable this (to fetch upstream data-browser UI rather than graph data, and not reformat any upstream HTML or JS)

      head['Content-Type'] = 'application/json' if %w(api.mixcloud.com proxy.c2.com).member? host

      head['Last-Modified']&.sub! /((ne|r)?s|ur)?day/, '' # abbr day name to 3-letter variant

      head['Link'].split(',').map{|link|             # read Link headers to request env
        ref, type = link.split(';').map &:strip
        if ref && type
          ref = ref.sub(/^</,'').sub />$/, ''
          type = type.sub(/^rel="?/,'').sub /"$/, ''
          env[:links][type.to_sym] = ref
        end} if head.has_key? 'Link'

      head['Referer'] = 'http://drudgereport.com/' if host&.match? /wsj\.com$/ # referer tweaks so stuff loads
      head['Referer'] = 'https://' + (host || env['HTTP_HOST']) + '/' if (path && %w(.gif .jpeg .jpg .png .svg .webp).member?(File.extname(path).downcase)) || parts.member?('embed')

      head['User-Agent'] = 'curl/7.82.0' if %w(po.st t.co).member? host # to prefer HTTP HEAD redirections e over procedural Javascript, advertise a basic user-agent

      logger.debug ["\e[7m🧽 ← 🗣 \e[0m ", HTTP.bwPrint(head)].join if debug? # clean debug-prints

      head
    end

    def hostGET
      dirMeta                        # directory metadata
      cookieCache                    # save/restore cookies
      case path
      when /(gen(erate)?|log)_?204$/ # connectivity check
        [204, {}, []]
      when '/feed'                   # subscription endpoint
        fetch adapt? ? Subscriptions[host] : nil
      when /^\/resizer/
        if (ps = path.split /\/\d+x\d+[^.]*\//).size > 1
          [302, {'Location' => 'https://' + ps[-1]}, []]
        else
          fetch
        end
      else
        if (λ = HostGET[host.downcase]) && adapt?
          λ[self]                    # adapted remote
        else
          deny? ? deny : fetch       # generic remote node
        end
      end
    end
    
    def icon
      [200,
       {'Content-Type' => 'image/png',
        'Expires' => (Time.now + 86400).httpdate}, [WebResource::HTML::SiteIcon]]
    end

    def inbox # redirect for address to current month's "mailbox" (timeline query) URI
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

    def normalize_charset c
      c = case c
          when /iso.?8859/i
            'ISO-8859-1'
          when /s(hift)?.?jis/i
            'Shift_JIS'
          when /utf.?8/i
            'UTF-8'
          else
            c
          end
      unless Encoding.name_list.member? c          # ensure charset is in encoding set
        logger.debug "⚠️ unsupported charset #{c} on #{uri}"
        c = 'UTF-8'                                # default charset
      end
      c
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

    def staticResponse format, body
      if format == 'text/html' && env[:proxy_href] # resolve proxy-hrefs
        body = Webize::HTML.resolve_hrefs body, env, true
      end

      head = {'Content-Type' => format,               # response header
              'Content-Length' => body.bytesize.to_s,
             'Expires' => (Time.now + 3e7).httpdate}

      [200, head, [body]]                             # response
    end

  end

  include HTTP

end
