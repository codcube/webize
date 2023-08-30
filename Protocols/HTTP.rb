%w(async async/barrier async/semaphore brotli cgi digest/sha2 open-uri rack resolv).map{|_| require _}

module Webize
  module HTTP
    Args = Webize.configList 'HTTP/arguments'            # permitted query arguments
    Methods = Webize.configList 'HTTP/methods'           # permitted HTTP methods
    ActionIcon = Webize.configHash 'style/icons/action'  # HTTP method -> char
    StatusIcon = Webize.configHash 'style/icons/status'  # status code (string) -> char
    StatusIcon.keys.map{|s|                              # status code (int) -> char
      StatusIcon[s.to_i] = StatusIcon[s]}

    def self.bwPrint kv
      kv.map{|k,v|
        "\e[38;5;7;7m#{k}\e[0m#{v}\n" }
    end

    # instantiate HTTP resource, call HTTP method and log request/response
    def self.call env
      return [403,{},[]] unless Methods.member? env['REQUEST_METHOD']

      env[:start_time] = Time.now                           # start timer
      env['SERVER_NAME'].downcase!                          # normalize hostname
      env.update HTTP.env                                   # init environment storage

      isPeer = PeerHosts.has_key? env['SERVER_NAME']        # peer node?
      isLocal = LocalAddrs.member?(PeerHosts[env['SERVER_NAME']] || env['SERVER_NAME']) # local node?

      u = (isLocal ? '/' : [isPeer ? :http : :https, '://', # scheme, host, path
          env['HTTP_HOST']].join).R.join RDF::URI(env['REQUEST_PATH']).path

      env[:base] = (Node u, env).freeze                     # external URI - immutable
             uri =  Node u, env                             # internal URI - mutable for follow-on requests of specific concrete-representations / variants

      uri.port = nil if [80,443,8000].member? uri.port      # strip default ports

      if env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # query string?
        env[:qs] = ('?' + env['QUERY_STRING'].sub(/^&+/,'').sub(/&+$/,'').gsub(/&&+/,'&')).R.query_values || {} # strip excess & and parse
        qs = env[:qs].dup                                   # external query
        Args.map{|k|                                        # (💻 <> 🖥) internal args
         env[k.to_sym]=qs.delete(k)||true if qs.has_key? k} # (💻 <> 🖥) internal args to request environment
        uri.query_values = qs unless qs.empty?              # (🖥 <> ☁️) external args to request URI
      end

      env[:client_tags] = env['HTTP_IF_NONE_MATCH'].strip.split /\s*,\s*/ if env['HTTP_IF_NONE_MATCH'] # parse eTag(s)
      env[:proxy_href] = isPeer || isLocal                  # relocate hrefs when proxying through local or peer hosts

      URI.blocklist if env['HTTP_CACHE_CONTROL'] == 'no-cache'      # refresh blocklist

      uri.send(env['REQUEST_METHOD']).yield_self{|status,head,body| # call request and inspect response
        inFmt = MIME.format_icon env[:origin_format]                # input format
        outFmt = MIME.format_icon head['Content-Type']              # output format
        color = env[:deny] ? '38;5;196' : (MIME::Color[outFmt]||0)  # format -> color
        referer = env['HTTP_REFERER'].R if env['HTTP_REFERER']      # referer

        Console.logger.info [(env[:base].scheme == 'http' && !isPeer) ? '🔓' : nil, # transport security

             if env[:deny]                                          # action taken:
               '🛑'                                                 # blocked
             elsif StatusIcon.has_key? status
               StatusIcon[status]                                   # status code
             elsif ActionIcon.has_key? env['REQUEST_METHOD']
               ActionIcon[env['REQUEST_METHOD']]                    # HTTP method
             elsif uri.offline?
               '🔌'                                                 # offline response
             end,

             (ENV.has_key?('http_proxy') ? '🖥' : '🐕' if env[:fetched]),          # upstream type: origin or proxy/middlebox

             referer ? ["\e[#{color}m",
                        referer.display_host,
                        "\e[0m → "] : nil,  # referer

             outFmt, ' ',                                                         # output format

             "\e[#{color}#{';7' if referer && referer.host != env[:base].host}m", # off-site referer

             (env[:base].display_host unless referer && referer.host == env[:base].host), env[:base].path, "\e[0m", # host, path

             ([' ⟵ ', inFmt, ' '] if inFmt && inFmt != outFmt),                   # input format, if transcoded

             (qs.map{|k,v|
                " \e[38;5;7;7m#{k}\e[0m #{v}"} if qs && !qs.empty?),              # query arguments

             head['Location'] ? [" → \e[#{color}m",
                                 (Node head['Location'], env).unproxyURI,
                                 "\e[0m"] : nil,                                  # redirect target

            ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join

        [status, head, body]}                                                     # response
    rescue Exception => e
      Console.logger.failure uri, e
      [500, {'Content-Type' => 'text/html; charset=utf-8'},
       uri.head? ? [] : ["<html><body class='error'>#{HTML.render({_: :style, c: Webize::CSS::SiteCSS})}500</body></html>"]]
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

    # blank environment structure
    def self.env
      {client_etags: [],
       feeds: [],
       links: {},
       qs: {}}
    end

    def self.Node uri, env
      Node.new(uri).env env
    end

  end
  class HTTP::Node < Resource
    include MIME

    # host adaptation runs on last proxy in chain
    def adapt?
      !ENV.has_key?('http_proxy')
    end

    def block domain
      File.open([Webize::ConfigPath, :blocklist, :domain].join('/'), 'a'){|list|
        list << domain << "\n"} # add to blocklist
      URI.blocklist             # read blocklist
      [302, {'Location' => Node(['//', domain].join).href}, []]
    end

    def cookieCache
      cookie = POSIX::Node join('/cookie')            # jar
      if env[:cookie] && !env[:cookie].empty?         # store cookie to jar
        cookie.write env[:cookie]
        logger.info [:🍯, host, env[:cookie]].join ' '
      end
      if cookie.file?                                 # load cookie from jar
        env['HTTP_COOKIE'] = cookie.node.read
        logger.debug [:🍪, host, env['HTTP_COOKIE']].join ' '
      end
    end

    # current (y)ear (m)onth (d)ay (h)our -> URI for timeslice
    def dateDir
      ps = parts
      loc = Time.now.utc.strftime(case ps[0].downcase
                                  when 'y'
                                    hdepth = 3 ; '/%Y/'
                                  when 'm'
                                    hdepth = 2 ; '/%Y/%m/'
                                  when 'd'
                                    hdepth = 1 ; '/%Y/%m/%d/'
                                  when 'h'
                                    hdepth = 0 ; '/%Y/%m/%d/%H/'
                                  else
                                  end)
      globbed = ps[1]&.match? GlobChars
      pattern = ['*/' * hdepth,                       # glob less-significant subslices inside slice
                 globbed ? nil : '*', ps[1],          # globify slug if bare
                 globbed ? nil : '*'] if ps.size == 2 # .. if slug provided

      qs = ['?', env['QUERY_STRING']] if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?

      [302,{'Location' => [loc, pattern, qs].join},[]] # redirect to date-dir
    end

    def debug?
      ENV['CONSOLE_LEVEL'] == 'debug'
    end

    def deny status = 200, type = nil
      env[:deny] = true 
      return [301, {'Location' => Node(['//', host, path].join).href}, []] if query&.match? Gunk # drop query
      ext = File.extname basename if path
      type, content = if type == :stylesheet || ext == '.css'
                        ['text/css', '']
                      elsif type == :font || %w(.eot .otf .ttf .woff .woff2).member?(ext)
                        ['font/woff2', HTML::SiteFont]
                      elsif type == :image || %w(.bmp .ico .gif .jpg .png).member?(ext)
                        ['image/png', HTML::SiteIcon]
                      elsif type == :script || ext == '.js'
                        ['application/javascript', "// URI: #{uri.match(Gunk) || host}"]
                      elsif type == :JSON || ext == '.json'
                        ['application/json','{}']
                      else
                        ['text/html; charset=utf-8', HTML::Document.new(uri).env(env).write]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => origin,
        'Content-Type' => type},
       head? ? [] : [content]]
    end

    # create navigation pointers in HTTP header
    def dirMeta
      root = !path || path == '/'
      self.path += '.rss' if host == 'www.reddit.com' && path && !%w(favicon.ico gallery wiki video).member?(parts[0]) && !path.index('.rss')
      if host && root                                            # up to parent domain
        env[:links][:up] = '//' + host.split('.')[1..-1].join('.')
      elsif !root                                                # up to parent path
        env[:links][:up] = [File.dirname(env['REQUEST_PATH']), '/', (env['QUERY_STRING'] && !env['QUERY_STRING'].empty?) ? ['?',env['QUERY_STRING']] : nil].join
      end
      env[:links][:down] = '*' if (!host || offline?) && dirURI? # down to children
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
        [302, {'Location' => Node(['//', host, path].join).href}, []]
      end
    end

    # fetch node(s) from local or remote host
    def fetch nodes=nil, **opts
      return fetchLocal nodes if offline? # return cache
      if storage.file?                    # cached node?
        return fileResponse if fileMIME.match?(FixedFormat) && !basename.match?(/index/i) # return immutable node
        cache = storage                   # cache reference
      elsif storage.directory? && (🐢 = POSIX::Node join('index.🐢'), env).exist? # cached directory index?
        cache = 🐢                        # cache reference
      end
      env['HTTP_IF_MODIFIED_SINCE'] = cache.mtime.httpdate if cache # timestamp for conditional fetch

      if nodes # async fetch node(s)
        env[:updates_only] = true # limit response to updates
        opts[:thru] = false       # craft our own HTTP response
        barrier = Async::Barrier.new
	semaphore = Async::Semaphore.new(16, parent: barrier)
        repos = []
        nodes.map{|n|
          semaphore.async do
            repos << (Node(n).fetchRemote **opts)
          end}
        barrier.wait
        respond repos
      else # fetch node
        fetchRemote
      end
    end

    # fetch resource and cache upstream and derived data
    def fetchHTTP thru: true                                # graph data only or full upstream HTTP response through to caller?
      ::URI.open(uri, headers.merge({open_timeout: 8, read_timeout: 8, redirect: false})) do |response|
        h = headers response.meta                           # response headera
        case env[:origin_status] = response.status[0].to_i  # response status
        when 204                                            # no content
          [204, {}, []]
        when 206                                            # partial content
          h['Access-Control-Allow-Origin'] ||= origin
          [206, h, [response.read]]
        else                                                # massage metadata, cache and return data
          body = HTTP.decompress h, response.read           # decompress body

          format = if path == '/feed' && adapt?             # format override on upstream /feed due to ubiquitous text/html and text/plain headers
                     'application/atom+xml'
                   elsif content_type = h['Content-Type']   # format defined in HTTP header
                     ct = content_type.split(/;/)
                     if ct.size == 2 && ct[1].index('charset') # charset defined in HTTP header
                       charset = ct[1].sub(/.*charset=/i,'')
                       charset = nil if charset.empty? || charset == 'empty'
                     end
                     ct[0]
                   elsif path && content_type = (fileMIMEsuffix File.extname path)
                     content_type
                   else
                     'application/octet-stream'
                   end
          format.downcase!                                              # normalize format identifier
                                                                        # detect in-band charset definition
          if !charset && format.index('html') && metatag = body[0..4096].encode('UTF-8', undef: :replace, invalid: :replace).match(/<meta[^>]+charset=['"]?([^'">]+)/i)
            charset = metatag[1]
          end
          charset = charset ? (normalize_charset charset) : 'UTF-8'     # normalize charset identifier
          body.encode! 'UTF-8', charset, invalid: :replace, undef: :replace if format.match? /(ht|x)ml|script|text/ # transcode to UTF-8
          format = 'text/html' if format == 'application/xml' && body[0..2048].match?(/(<|DOCTYPE )html/i) # detect HTML served w/ XML MIME
          repository = (readRDF format, body).persist env, self         # read and cache graph data
          (print MIME.format_icon format; return repository) if !thru   # return graph data, or
                                                                        # HTTP Response with graph or static/unmodified-upstream data
          doc = storage.document                                        # static cache
          if (formats = RDF::Format.content_types[format]) &&           # content type
             (extensions = formats.map(&:file_extension).flatten) &&    # suffixes for content type
             !extensions.member?((File.extname(doc)[1..-1]||'').to_sym) # upstream suffix in mapped set?
            doc = [(link = doc), '.', extensions[0]].join               # append valid suffix
            FileUtils.ln_s File.basename(doc), link unless dirURI? || File.exist?(link) || File.symlink?(link) # link canonical name to storage name
          end

          File.open(doc, 'w'){|f| f << format == 'text/html' ? HTML.cachestamp(body, self) : body } # update cache

          if timestamp = h['Last-Modified']                             # HTTP timestamp?
            if t = Time.httpdate(timestamp) rescue nil                  # parse timestamp
              FileUtils.touch doc, mtime: t                             # set timestamp on filesystem
              repository << RDF::Statement.new(self, Date.R, t.iso8601) # set timestamp in RDF
            end
          end
          if env[:notransform] || format.match?(FixedFormat)
            staticResponse format, body                                 # response in upstream format
          else
            env[:origin_format] = format                                # upstream format
            respond [repository], format                                # response in content-negotiated format
          end
        end
      end
    rescue Exception => e
      raise unless e.respond_to?(:io) && e.io.respond_to?(:status)
      status = e.io.status[0].to_i                          # status raised to exception by HTTP library
      case status.to_s
      when /30[12378]/                                      # redirect
        location = e.io.meta['location']
        dest = Node join location
        if !thru
          logger.warn "⚠️ redirected #{uri} → #{location} but configured to not follow - update source reference"
        elsif no_scheme == dest.no_scheme
          if scheme == 'https' && dest.scheme == 'http'     # 🔒downgrade
            logger.warn "🛑 downgrade redirect #{dest}"
            fetchLocal if thru
          elsif scheme == 'http' && dest.scheme == 'https'  # 🔒upgrade
            logger.debug "🔒 upgrade redirect #{dest}"
            dest.fetchHTTP
          else                                              # redirect loop or non-HTTP protocol
            logger.warn "🛑 not following #{uri} → #{dest} redirect"
            fetchLocal if thru
          end
        else                                                # redirect
          [status, {'Location' => dest.href}, []]
        end
      when /304/                                            # origin unmodified
        fetchLocal if thru
      when /300|[45]\d\d/                                   # not allowed/available/found
        env[:origin_status] = status
        head = headers e.io.meta
        body = HTTP.decompress(head, e.io.read).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        repository ||= RDF::Repository.new
        RDF::Reader.for(content_type: 'text/html').new(body, base_uri: self){|g|repository << g} if head['Content-Type']&.index 'html'
        head['Content-Length'] = body.bytesize.to_s
        if path == '/favicon.ico' && status / 100 == 4 # set default icon
          env.delete :origin_status
          storage.write HTML::SiteIcon
          fileResponse
        elsif !thru
          repository
        elsif env[:notransform]
          [status, head, [body]] # static response data
        else
          respond [repository] # dynamic/transformable response data
        end
      else
        raise
      end
    end

    def fetchLocal nodes = nil
      return fileResponse if !nodes && storage.file? && (format = fileMIME) && # file if cached and one of:
                       (env[:notransform] ||                # (mimeA → mimeB) transform disabled by client
                        format.match?(MIME::FixedFormat) || # (mimeA → mimeB) transform disabled by server
      (format == selectFormat(format) && !MIME::ReFormat.member?(format))) # (mimeA → mimeA) reformat disabled
      repos = (nodes || storage.nodes).map{|x|              # load node(s)
        if x.file?                                          # file?
          x.file_triples x.readRDF                          # read file + filesystem metadata
        elsif x.directory?                                  # directory?
          x.dir_triples RDF::Repository.new                 # read directory metadata
        end}
      dirMeta                                               # 👉 storage-adjacent nodes
      timeMeta unless host                                  # 👉 timeline-adjacent nodes
      respond repos                                         # response
    end

    def fetchRemote **opts
      start_time = Time.now
      env[:fetched] = true                                  # denote network-fetch for logger
      case scheme                                           # request scheme
      when 'gemini'
        Gemini::Node.new(uri).env(env).fetch                # fetch w/ Gemini protocol
      when /https?/
        if deny_domain? && env[:proxy_href]                 # domain adapted/rewritten by proxy
          self.port = 8000                                  # set proxy port
          insecure.fetchHTTP **opts                         # fetch w/ HTTP - implicit proxy (DNS or routing config)
        elsif ENV.has_key?('http_proxy')
          insecure.fetchHTTP **opts                         # fetch w/ HTTP - explicit proxy (environment variable)
        else
          fetchHTTP **opts                                  # fetch w/ HTTP(S)
        end
      when 'spartan'                                        # fetch w/ Spartan
        fetchSpartan
      else
        logger.warn "⚠️ unsupported scheme #{uri}"           # unsupported scheme
        opts[:thru] == false ? nil : notfound
      end
    rescue Exception => e                                   # warn on error
      env[:warning] ||= []
      env[:warning].push [{_: :span, c: e.class},
                          {_: :a, href: href, c: uri},
                          CGI.escapeHTML(e.message),
                          {_: :b, c: [:⏱️, Time.now - start_time, :s]}, '<br>']
      puts [:⚠️, uri, e.class, e.message].join ' '
      opts[:thru] == false ? nil : notfound
    end

    # URI -> ETag
    def fileETag
      Digest::SHA2.hexdigest [uri, storage.mtime, storage.size].join
    end

    def fileResponse
      if env[:client_etags].include?(etag = fileETag)     # cached at client
        return [304, {}, []]
      end

      Rack::Files.new('.').serving(Rack::Request.new(env), storage.fsPath).yield_self{|s,h,b|
        case s                                            # status
        when 200
          s = env[:origin_status] if env[:origin_status]  # upstream status
        when 304
          return [304, {}, []]                            # cached at client
        end
        format = fileMIME                                 # file format
        h['content-type'] = format
        h['ETag'] = etag
        h['Expires'] = (Time.now + 3e7).httpdate if format.match? FixedFormat
        h['Last-Modified'] ||= storage.mtime.httpdate
        [s, h, b]}
    end
 
    def GET
      return hostGET if host                  # remote node - canonical URI
      ps = parts ; p = ps[0]                  # parse path
      return fetchLocal unless p              # local node - / or no path
      return unproxy.hostGET if p[-1] == ':' && ps.size > 1        # remote node - proxy URI w/ scheme
      return unproxy.hostGET if p.index('.') && p != 'favicon.ico' # remote node - proxy URI sans scheme
      return dateDir if %w{m d h y}.member? p # year/month/day/hour redirect
      return block parts[1] if p == 'block'   # block domain action
      return fetch uris if extname == '.u' && query == 'fetch'
      fetchLocal                              # local node
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
      logger.debug ["\e[7m🥩 ← 🗣 \e[0m #{uri}\n", HTTP.bwPrint(raw)].join if debug? # raw debug-prints

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

      head['Accept'] = ['text/turtle', head['Accept']].join ',' unless env[:notransform] || head['Accept']&.match?(/text\/turtle/) # accept graph-data - ?notransform disables this and HTML reformatting to fetch upstream data-browser/UI-code rather than graph data

      head['Content-Type'] = 'application/json' if %w(api.mixcloud.com).member? host

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
      head.delete 'Referer' if host == 'www.reddit.com' # existence of referer causes empty RSS feed

      head['User-Agent'] = 'curl/7.82.0' if %w(po.st t.co).member? host # to prefer HTTP HEAD redirections e over procedural Javascript, advertise a basic user-agent

      logger.debug ["\e[7m🧽 ← 🗣 \e[0m #{uri}\n", HTTP.bwPrint(head)].join if debug? # clean debug-prints

      head
    end

    # declarative host categories
    URLHosts = Webize.configList 'hosts/url'

    def hostGET
      return (q = query_values || {} # redirect URL rehost to origin
              dest = q['url'] || q['u'] || q['q']
              dest ? [301, {'Location' => Node(dest).href}, []] : notfound) if URLHosts.member? host
      return [301, {'Location' => Node(['//www.youtube.com/watch?v=', path[1..-1]].join).href}, []] if host == 'youtu.be'

      dirMeta      # directory metadata
      cookieCache  # save/restore cookies
      case path
      when /(gen(erate)?|log)_?204$/ # connectivity check
        [204, {}, []]
      when '/feed' # subscription aggregation node
        fetch adapt? ? Feed::Subscriptions[host] : nil
      else         # generic remote node
        deny? ? deny : fetch
      end
    end

    def linkHeader
      return unless env.has_key? :links
      env[:links].map{|type,uri|
        "<#{uri}>; rel=#{type}"}.join(', ')
    end

    def link_icon
      return unless env[:links].has_key? :icon
      fav = POSIX::Node join '/favicon.ico'                                 # default location
      icon = env[:links][:icon] = POSIX::Node env[:links][:icon], env       # icon location
      if !icon.dataURI? && icon.path != fav.path && icon != self &&         # if icon is in non-default location and
         !icon.directory? && !fav.exist? && !fav.symlink?                   # default location is available:
        fav.mkdir                                                           # create container
        FileUtils.ln_s (icon.node.relative_path_from fav.dirname), fav.node # link icon to default location
      end
    end

    def Node uri
      (HTTP::Node.new uri).env env
    end

    def normalize_charset c
      c = case c
          when /iso.?8859/i
            'ISO-8859-1'
          when /s(hift)?.?jis/i
            'Shift_JIS'
          when /utf.?8/i
            'UTF-8'
          when /win.*1252/i
            'Windows-1252'
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
             when /html/
               HTML::Document.new(uri).env(env).write
             when /atom|rss|xml/
               Feed::Document.new(uri).env(env).write
             end

      [404, {'Content-Type' => format}, head? ? nil : [body ? body : '']]
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

    # default response - serialize graph per content-negotiation preference
    def respond repositories, defaultFormat = 'text/html'
      status = env[:origin_status] || 200  # response status
      format = selectFormat defaultFormat  # response format
      format += '; charset=utf-8' if %w{text/html text/turtle}.member? format
      head = {'Access-Control-Allow-Origin' => origin,
              'Content-Type' => format,
              'Last-Modified' => Time.now.httpdate,
              'Link' => linkHeader}        # response header
      return [status, head, nil] if head?  # header-only response

      body = case format                   # response body
             when /html/                   # serialize HTML
               link_icon
               HTML::Document.new(uri).env(env).write JSON.fromGraph repositories
             when /atom|rss|xml/           # serialize Atom/RSS
               Feed::Document.new(uri).env(env).write JSON.fromGraph repositories
             else                          # serialize RDF
               if writer = RDF::Writer.for(content_type: format)
                 out = RDF::Repository.new
                 repositories.map{|r| out << r }
                 out.dump writer.to_sym, base_uri: self
               else
                 logger.warn "⚠️  RDF::Writer undefined for #{format}" ; ''
               end
             end

      head['Content-Length'] = body.bytesize.to_s # response size
      [status, head, [body]]                      # response
    end

    def selectFormat default = nil                          # default-format argument
      default ||= 'text/html'                               # default when unspecified
      return default unless env.has_key? 'HTTP_ACCEPT'      # no preference specified
      category = (default.split('/')[0] || '*') + '/*'      # format-category wildcard symbol
      all = '*/*'                                           # any-format wildcard symbol

      index = {}                                            # build (q-value → format) index
      env['HTTP_ACCEPT'].split(/,/).map{|e|                 # header values
        fmt, q = e.split /;/                                # (MIME, q-value) pair
        i = q && q.split(/=/)[1].to_f || 1                  # default q-value
        index[i] ||= []                                     # q-value entry
        index[i].push fmt.strip}                            # insert format at q-value

      index.sort.reverse.map{|_, accepted|                  # search in descending q-value order
        return default if accepted.member? all              # anything accepted here
        return default if accepted.member? category         # category accepted here
        accepted.map{|format|
          return format if RDF::Writer.for(:content_type => format) || # RDF writer available for format
             ['application/atom+xml','text/html'].member?(format)}}    # non-RDF writer available
      default                                               # search failure, use default
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

    def storage
      POSIX::Node self, env
    end

    # URI -> HTTP headers
    def timeMeta
      n = nil # next-page locator
      p = nil # prev-page locator

      # path components
      ps = parts # all parts
      dp = []    # datetime parts
      dp.push ps.shift.to_i while ps[0] && ps[0].match(/^[0-9]+$/)

      q = (env['QUERY_STRING'] && !env['QUERY_STRING'].empty?) ? ('?'+env['QUERY_STRING']) : ''

      case dp.length
      when 1 # Y
        year = dp[0]
        n = '/' + (year + 1).to_s
        p = '/' + (year - 1).to_s
      when 2 # Y-m
        year = dp[0]
        m = dp[1]
        n = m >= 12 ? "/#{year + 1}/#{01}" : "/#{year}/#{'%02d' % (m + 1)}"
        p = m <=  1 ? "/#{year - 1}/#{12}" : "/#{year}/#{'%02d' % (m - 1)}"
      when 3 # Y-m-d
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          p = (day-1).strftime('/%Y/%m/%d')
          n = (day+1).strftime('/%Y/%m/%d')
        end
      when 4 # Y-m-d-H
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          hour = dp[3]
          p = hour <=  0 ? (day - 1).strftime('/%Y/%m/%d/23') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour-1)))
          n = hour >= 23 ? (day + 1).strftime('/%Y/%m/%d/00') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour+1)))
        end
      end

      # previous, next, parent pointers
      env[:links][:up] = [nil, dp[0..-2].map{|n| '%02d' % n}, '*', ps].join('/') + q if dp.length > 1 && ps[-1] != '*' && ps[-1]&.match?(GlobChars)
      env[:links][:prev] = [p, ps].join('/') + q + '#prev' if p
      env[:links][:next] = [n, ps].join('/') + q + '#next' if n
    end

    # unproxy request/environment URLs
    def unproxy
      r = unproxyURI                                                                             # unproxy URI
      r.scheme ||= 'https'                                                                       # default scheme
      r.host = r.host.downcase if r.host.match? /[A-Z]/                                          # normalize hostname
      env[:base] = Node r.uri                                                                    # update base URI and
      env['HTTP_REFERER'] = Node(env['HTTP_REFERER']).unproxyURI.to_s if env.has_key? 'HTTP_REFERER' # referer URI
      r                                                                                          # origin URI
    end

    # proxy URI -> canonical URI
    def unproxyURI
      p = parts[0]
      return self unless p&.index /[\.:]/ # scheme or DNS name required
      Node [(p && p[-1] == ':') ? path[1..-1] : ['/', path], query ? ['?', query] : nil].join
    end

    # URIs from uri-list
    def uris
      return [] unless extname == '.u'
      readRDF.query(RDF::Query::Pattern.new :s, Contains.R, :o).objects
    end

  end
end
