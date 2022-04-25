# coding: utf-8
%w(async brotli cgi digest/sha2 open-uri rack resolv).map{|_| require _}

class WebResource
  module URIs
    FileModified = {deny: 0}
  end
  module HTTP
    include URIs

    Args = %w(cookie find fullContent group notransform offline order sort view) # client<>proxy arguments
    HostGET = {}
    PeerHosts = Hash[*File.open([ENV['PREFIX'],'/etc/hosts'].join).readlines.map(&:chomp).map{|l|
                       addr, *names = l.split
                       names.map{|host|
                         [host, addr]}}.flatten]
    PeerAddrs = PeerHosts.invert
    LocalAddrs = Socket.ip_address_list.map &:ip_address
    Methods = %w(GET HEAD OPTIONS POST PUT)
    R304 = [304, {}, []]

    StatusColor = {
      200 => '#333',
      304 => :green,
      401 => :orange,
      403 => :yellow,
      404 => :gray,
      503 => '#fff',
      504 => '#f0c'}

    StatusIcon = {
      200 => nil,
      202 => '➕',
      204 => '✅',
      206 => '🧩',
      301 => '➡️',
      302 => '➡️',
      303 => '➡️',
      304 => '✅',
      401 => '🚫',
      403 => '🚫',
      404 => '❓',
      410 => '❌',
      500 => '🚩',
      503 => '🔌',
      504 => '🔌'}

    def action_icon
      if env[:deny]
        '🛑'
      elsif offline?
        '🔌'
      else
        case env['REQUEST_METHOD']
        when 'HEAD'
          '🗣'
        when 'OPTIONS'
          '🔧'
        when /P(OS|U)T/
          '📝'
        when 'GET'
          if env[:fetched] # denote middlebox or origin fetch
            ENV.has_key?('HTTP_PROXY') ? '🖥' : '🐕'
          end
        end
      end
    end

    # respond from local cache
    def cacheResponse
      return fileResponse if file? && (format = fileMIME) && # static response if
                             (env[:notransform] ||          # format-transform disabled,
                              format.match?(FixedFormat) || # format-transform unavailable, or
                              (format==selectFormat(format) && !ReFormat.member?(format))) # reformat unavailable

      q = env[:qs]                                          # query modes:
      nodes = if directory?
                if q['f'] && !q['f'].empty?                 # FIND exact
                  summarize = !env[:fullContent]
                  find q['f']
                elsif q['find'] && !q['find'].empty?        # FIND substring
                  summarize = !env[:fullContent]
                  find '*' + q['find'] + '*'
                elsif q['q'] && !q['q'].empty?              # GREP
                  grep
                else                                        # LS dir
                  [self, *join('{index,readme,README}*').R(env).glob]
                end
              elsif file?                                   # LS file
                [self]
              elsif fsPath.match? GlobChars                 # GLOB
                if q['q'] && !q['q'].empty?
                  if (g = nodeGlob).empty?
                    []
                  else
                    fromNodes nodeGrep g[0..999]            # GREP in GLOB
                  end
                else
                  summarize = !env[:fullContent]
                  glob                                      # arbitrary GLOB
                end
              else
                fromNodes Pathname.glob fsPath+'.*'         # default GLOB
              end

      if summarize                                          # 👉 unsummarized
        env[:links][:down] = HTTP.qs q.merge({'fullContent' => nil})
        nodes.map! &:preview
      end
      if env[:fullContent] && q.respond_to?(:except)        # 👉 summarized
        env[:links][:up] = HTTP.qs q.except('fullContent')
      end

      nodes.map &:loadRDF                                   # load node(s)
      graphResponse                                         # response
    end

    def self.bwPrint kv
      kv.map{|k,v|
        print "\e[38;5;7;7m#{k}\e[0m#{v}"}
      print "\n"
    end

    # HTTP entry-point
    def self.call env
      # initialize environment
      env[:start_time] = Time.now                           # start timer
      env['SERVER_NAME'].downcase!                          # normalize hostname
      env[:client_tags] = env['HTTP_IF_NONE_MATCH'].strip.split /\s*,\s*/ if env['HTTP_IF_NONE_MATCH'] # parse etags
      env.update HTTP.env                                   # storage fields

      # construct URI from header fields
      isPeer = PeerHosts.has_key? env['SERVER_NAME']        # peer node?
      isLocal = LocalAddrs.member?(PeerHosts[env['SERVER_NAME']]||env['SERVER_NAME']) # local node?
      uri = if isLocal
              env[:proxy_href] = true                       # relocate hrefs to local URI space
              '/'                                           # local node
            else                                            # remote node
              env[:proxy_href] = isPeer
              [isPeer ? :http : :https, '://', env['HTTP_HOST']].join
            end.R.join(env['REQUEST_PATH']).R env
      uri.port = nil if [80,443,8000].member? uri.port      # drop redundant port information
      if env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # query string?
        env[:qs] = ('?' + env['QUERY_STRING'].sub(/^&+/,'').sub(/&+$/,'').gsub(/&&+/,'&')).R.query_values || {}
        qs = env[:qs].dup                                   # strip excess &s, parse and memoize query
        Args.map{|k|
         env[k.to_sym]=qs.delete(k)||true if qs.has_key? k} # consume (client <> proxy) args, store in request environment
        uri.query_values = qs unless qs.empty?              # retain (proxy <> origin) args, store in request URI
      end
      env[:base] = uri.to_s.R env                           # set base URI in environment

      # request
      if Verbose
        print "\e[7m💻 → 🖥 #{uri}\e[0m " ; bwPrint env
      end
      uri.send(env['REQUEST_METHOD']).yield_self{|status, head, body|
        if Verbose
          print "\e[7m💻 ← 🖥 #{uri}\e[0m " ; bwPrint head
        end

        # log request
        fmt = uri.format_icon head['Content-Type']                                                       # iconify format
        color = env[:deny] ? '38;5;196' : (FormatColor[fmt] || 0)                                        # colorize format
        puts [[(env[:base].scheme == 'http' && !isPeer) ? '🔓' : nil,                                    # denote insecure transport
               (!env[:deny] && !uri.head? && head['Content-Type'] != env[:origin_format]) ? fmt : nil,   # downstream format if != upstream format
               status == env[:origin_status] ? nil : StatusIcon[status],                                 # downstream status if != upstream format
               uri.action_icon,                                                                          # HTTP method
               env[:origin_format] ? (uri.format_icon env[:origin_format]) : nil,                        # upstream format
               StatusIcon[env[:origin_status]],                                                          # upstream status
               ([env[:repository].size,'⋮'].join if env[:repository] && env[:repository].size > 0)].join,# RDF graph triple-size
              env['HTTP_REFERER'] ? ["\e[#{color}m", env['HTTP_REFERER'], "\e[0m→"] : nil,               # referer location
              "\e[#{color}#{env[:base].host && env['HTTP_REFERER'] && !env['HTTP_REFERER'].index(env[:base].host) && ';7' || ''}m", # invert colors if off-site referer
              status == 206 ? Rack::Utils.unescape_path(env[:base].basename) : env[:base], "\e[0m",      # request URI
              head['Location'] ? ["→\e[#{color}m", head['Location'], "\e[0m"] : nil,                     # redirected location
              env[:warning] ? ["\e[38;5;226;7m⚠️", env[:warning], "\e[0m"] : nil,                         # warnings
              Verbose ? [env['HTTP_ACCEPT'], head['Content-Type']].compact.join(' → ') : nil,            # MIME headers
             ].flatten.compact.map{|t|
          t.to_s.encode 'UTF-8'}.join ' '

        # response
        [status, head, body]}
    rescue Exception => e
      puts env[:base], e.class, e.message, e.backtrace
      [500, {'Content-Type' => 'text/html; charset=utf-8'}, uri.head? ? [] : ["<html><body class='error'>#{HTML.render [{_: :style, c: SiteCSS}, {_: :script, c: SiteJS}, uri.uri_toolbar]}500</body></html>"]]
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
      puts [e.class, e.message].join " "
      head['Content-Encoding'] = encoding
      body
    end

    def HTTP.env
      {client_etags: [],
       feeds: [],
       links: {},
       qs: {}}
    end

    def deny status = 200, type = nil
      env[:deny] = true
      ext = File.extname basename if path
      type, content = if type == :stylesheet || ext == '.css'
                        ['text/css', '']
                      elsif type == :font || %w(.eot .otf .ttf .woff .woff2).member?(ext)
                        ['font/woff2', SiteFont]
                      elsif type == :image || %w(.bmp .ico .gif .jpg .png).member?(ext)
                        ['image/png', SiteIcon]
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

    def deny?
      return true if BlockedSchemes.member? scheme          # scheme filter
      denyDNS?                                              # domain filter
    end

    def denyDNS?
      return if !host || AllowHosts.member?(host)           # explicitly allowed hostname
      c = DenyDomains                                       # cursor at base
      domains.find{|n|                                      # tokenize domains, init iterative search
        return unless c = c[n]                              # advance cursor to domain
                      c.empty? }                            # domain leaf in deny tree?
    end

    def enter_container
      [301, {'Location' => [env['REQUEST_PATH'], '/', env['QUERY_STRING'] ? ['?', env['QUERY_STRING']] : nil].join}, []]
    end

    def env e = nil
      if e
        @env = e
        self
      else
        @env ||= {}
      end
    end

    # fetch data from cache and/or remote
    def fetch
      return cacheResponse if offline?                      # offline, return cache
      if file?                                              # cached file?
        return fileResponse if fileMIME.match?(FixedFormat) && !basename.match?(/index/i) # return cached static-file
        env[:cache] = self                                  # reference for conditional fetch
      elsif directory? && (🐢 = join('index.🐢').R env).exist? # cached index?
        🐢.preview.loadRDF                                  # fetch index to graph
      end

      env[:fetched] = true                                  # note fetch for logger
      case scheme                                           # request scheme
      when 'ftp'
        fetchFTP                                            # fetch w/ FTP
      when 'gemini'
        fetchGemini                                         # fetch w/ Gemini
      when 'http'
        fetchHTTP                                           # fetch w/ HTTP
      when 'https'
        if ENV.has_key?('HTTP_PROXY')
          insecure.fetchHTTP                                # fetch w/ HTTP to private-network peer
        elsif (PeerAddrs.has_key? Resolv.getaddress host rescue false)
          url = insecure
          url.port = 8000
          url.fetchHTTP                                     # fetch w/ HTTP to private-network peer
        else
          fetchHTTP                                         # fetch w/ HTTPS
        end
      else
        puts "⚠️ unsupported scheme in #{uri}"; notfound     # unsupported scheme
      end

    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError, OpenSSL::SSL::SSLError, RuntimeError, SocketError => e
      env[:warning] = [e.class, e.message].join ' '         # warn on error/fallback condition
      if scheme == 'https'                                  # HTTPS failure?
        insecure.fetchHTTP rescue notfound                  # fallback to HTTP
      else
        notfound
      end
    end

    def fetchFTP
      fetchHTTP
    end

    # fetch node to graph and cache
    def fetchHTTP format: nil, thru: true                   # options: MIME (override erroneous origin), HTTP response for caller
      head = headers.merge({redirect: false})               # parse client headers, disable automagic/hidden redirect following
      unless env[:notransform]                              # query ?notransform for upstream UI on content-negotiating servers
        head['Accept'] = ['text/turtle', head['Accept']].join ',' unless head['Accept']&.match? /text\/turtle/ # accept 🐢/turtle
      end
      head['If-Modified-Since'] = env[:cache].mtime.httpdate if env[:cache] # timestamp for conditional fetch
      if Verbose
        print "\e[7m🖥 → ☁️  #{uri}\e[0m "
        HTTP.bwPrint head
      end
      URI.open(uri, head) do |response|                     # HTTP(S) fetch
        h = headers response.meta                           # response metadata
        if Verbose
#          print '🥩 ← ☁️  '                                 # raw upstream headers
#          HTTP.bwPrint response.meta
          print "\e[7m🧽 ← ☁️ \e[0m "                        # clean headers
          HTTP.bwPrint h
        end
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
                puts "⚠️ unsupported charset #{charset}" if Verbose
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
               (extensions = formats.map(&:file_extension).flatten) && # mapped suffixes for content-type
               !extensions.member?(ext)                     # upstream suffix not mapped for content-type
              file = [(link = file), '.', extensions[0]].join # append suffix and display notice
              FileUtils.ln_s File.basename(file), link      # link upstream name to local name
              puts ['extension', ext, 'for', format, 'not in (', extensions.join(', '), '), linking', file].join ' 'if Verbose
            end
            File.open(file, 'w'){|f| f << body }            # cache

            if timestamp = h['Last-Modified']               # HTTP provided timestamp
              timestamp.sub! /((ne|r)?s|ur)?day/, ''        # still full dayname declarations
              if ts = Time.httpdate(timestamp) rescue nil   # parse timestamp
                FileUtils.touch file, mtime: ts             # cache timestamp
              else
                puts '⚠️ unparsed timestamp:' + h['Last-Modified'] if Verbose
              end
            end

            if reader = RDF::Reader.for(content_type: format) # reader defined for format?
              env[:repository] ||= RDF::Repository.new      # initialize RDF repository
              if ts                                         # header to RDF
                env[:repository] << RDF::Statement.new(self, Date.R, ts.iso8601)
                case format
                when /image/
                  env[:repository] << RDF::Statement.new(self, Type.R, Image.R)
                when /video/
                  env[:repository] << RDF::Statement.new(self, Type.R, Video.R)
                end
              end
              reader.new(body, base_uri: self, path: file){|g|env[:repository] << g} # read RDF
              if format == 'text/html' && reader != RDF::RDFa::Reader                # read RDFa
                RDF::RDFa::Reader.new(body, base_uri: self){|g|env[:repository] << g} rescue puts :RDFa_error
              end
            else
              puts "⚠️ Reader undefined for #{format}" if Verbose
            end unless format.match?(/octet-stream/) || body.empty?
          else
            puts "⚠️ format undefined on #{uri}" if Verbose
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
            puts [:🍯, host, h['Set-Cookie']].join ' ' if Verbose
          end

          if env[:client_etags].include? h['ETag']          # client has entity
            R304                                            # no content
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
        dest = join(e.io.meta['location']).R env
        if no_scheme == dest.no_scheme                      # alternate scheme
          puts "⚠️  downgrade #{uri} ➡️ #{dest}" if scheme == 'https' && dest.scheme == 'http'
          dest.fetchHTTP
        else
          [status, {'Location' => dest.href}, []]
        end
      when /304/                                            # origin unmodified
        cacheResponse
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
        env[:notransform] ? [status, head, [body]] : env[:base].cacheResponse # origin or cache response
      else
        raise
      end
    end

    def fileETag
      Digest::SHA2.hexdigest [uri, mtime, node.size].join         # mint ETag for file version
    end

    def fileResponse
      return R304 if env[:client_etags].include?(etag = fileETag) # cached at client
      Rack::Files.new('.').serving(Rack::Request.new(env), fsPath).yield_self{|s,h,b|
        case s                                                    # status
        when 200
          s = env[:origin_status] if env[:origin_status]          # upstream status
        when 304
          return R304                                             # cached at client
        end
        format = fileMIME                                         # file format
        h['Content-Type'] = format
        h['Content-Type'] = 'application/javascript; charset=utf-8' if h['Content-Type']=='application/javascript'
        h['ETag'] = etag
        h['Expires'] = (Time.now + 3e7).httpdate if format.match? FixedFormat
        h['Last-Modified'] ||= mtime.httpdate
        [s, h, b]}                                                # response
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      if !host
        p = parts[0]                                        # read path selector
        if !p                                               # root node
          homepage
        elsif p[-1] == ':'                                  # proxy URI with scheme
          unproxy.hostHandler                               # remote node
        elsif p == 'favicon.ico'                            # site icon
          [200, {'Content-Type' => 'image/png'}, [SiteIcon]]
        elsif %w(robots.txt).member? p                      # robots file
          notfound
        elsif p.index '.'                                   # proxy URI, undefined scheme
          unproxy(true).hostHandler                         # remote node
        elsif %w{m d h y}.member? p                         # year/month/day/hour abbr
          dateDir                                           # redirect to year/month/day/hour dir
        elsif p=='mailto' && parts.size==2                  # redirect to mailbox
          [302, {'Location' => ['/m/', (parts[1].split(/[\W_]/) - BasicSlugs).map(&:downcase).join('.'), '?view=table&sort=date'].join}, []]
        elsif directory? && !dirURI?                        # container without trailing slash
          enter_container                                   # redirect to container
        else
          dirMeta                                           # 👉 storage-adjacent nodes
          timeMeta                                          # 👉 timeline-adjacent nodes
          cacheResponse                                     # local resource
        end
      else
        hostHandler                                         # remote resource
      end
    end

    def graphResponse defaultFormat = 'text/html'
      return notfound if !env.has_key?(:repository)||env[:repository].empty? # nothing found
      status = env[:origin_status] || 200                   # response status
      format = selectFormat defaultFormat                   # response format
      format += '; charset=utf-8' if %w{text/html text/turtle}.member? format
      head = {'Access-Control-Allow-Origin' => origin,      # response header
              'Content-Type' => format,
              'Link' => linkHeader}
      return [status, head, nil] if head?                   # header-only response

      body = case format                                    # response body
             when /html/
               htmlDocument treeFromGraph                   # serialize HTML
             when /atom|rss|xml/
               feedDocument treeFromGraph                   # serialize Atom/RSS
             else                                           # serialize RDF
               if writer = RDF::Writer.for(content_type: format)
                 env[:repository].dump writer.to_sym, base_uri: self
               else
                 puts "no Writer for #{format}"
                 ''
               end
             end

      head['Content-Length'] = body.bytesize.to_s           # response size
      [status, head, [body]]                                # response
    end

    def has_handler?
      HostGET.has_key? host.downcase
    end

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # header and status
    end

    def head?; env['REQUEST_METHOD'] == 'HEAD' end

    # client<>proxy connection and server-specific headers not repeated on proxy<>origin connection
    SingleHopHeaders = %w(async.http.request connection host if-modified-since if-none-match keep-alive path-info query-string
 remote-addr request-method request-path request-uri script-name server-name server-port server-protocol server-software
 te transfer-encoding unicorn.socket upgrade upgrade-insecure-requests version via x-forwarded-for)

    # headers for export to external clients and servers
    def headers raw = nil
      raw ||= env || {}                                     # raw headers
      head = {}                                             # cleaned headers
      raw.map{|k,v|                                         # inspect (k,v) pairs
        unless k.class != String || k.index('rack.') == 0   # skip internal headers
          key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip prefix and tokenize
            if %w{cf cl csrf ct dfe dnt id spf utc xss xsrf}.member? t
              t.upcase                                      # upcase acronym
            elsif 'etag' == t
              'ETag'                                        # partial acronym
            else
              t.capitalize                                  # capitalize word
            end}.join '-'                                   # join words
          head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless SingleHopHeaders.member? key.downcase # set header
        end}

      head['Referer'] = 'http://drudgereport.com/' if host&.match? /wsj\.com$/
      head['Referer'] = 'https://' + (host || env['HTTP_HOST']) + '/' if (path && %w(.gif .jpeg .jpg .png .svg .webp).member?(File.extname(path).downcase)) || parts.member?('embed')
      head['User-Agent'] = 'curl/7.82.0' if %w(po.st t.co).member? host # to prefer HTTP HEAD redirections e over procedural Javascript, advertise a basic user-agent
      head
    end

    def hostHandler
      URIs.denylist                                         # refresh denylist
      qs = query_values || {}                               # parse query
      dirMeta

      cookie = join('/cookie').R                            # cookie-jar URI
      if env[:cookie] && !env[:cookie].empty?               # store cookie to jar
        cookie.writeFile env[:cookie]
        puts [:🍯, host, env[:cookie]].join ' ' if Verbose
      end
      if cookie.file?                                       # read cookie from jar
        env['HTTP_COOKIE'] = cookie.node.read
        puts [:🍪, host, env['HTTP_COOKIE']].join ' ' if Verbose
      end

      if parts[-1]&.match? /^(gen(erate)?|log)_?204$/       # 204 response w/o origin roundtrip
        [204, {}, []]
      elsif has_handler?                                    # host handler exists?
        if ENV.has_key? 'HTTP_PROXY'
          fetch                                             # node at chained proxy
        else
          HostGET[host.downcase][self]                      # adaptor at origin-facing proxy
        end
      elsif query&.match? Gunk                              # drop gunked query
        [301,{'Location' => ['//', host, path].join.R(env).href},[]]
      elsif host.match?(/\.(amazonaws|cloudfront)\.(com|net)$/) && uri.match?(/\.(jpe?g|png|webp)$/i)
        fetch
      elsif deny?                                           # denied request
        deny
      elsif offline? && directory? && !dirURI?              # enter directory
        enter_container
      else                                                  # remote node
        fetch
      end
    end

    def insecure
      _ = dup.env env
      _.scheme = 'http' if _.scheme == 'https'
      _.env[:base] = _
    end

    def linkHeader
      return unless env.has_key? :links
      env[:links].map{|type,uri|
        "<#{uri}>; rel=#{type}"}.join(', ')
    end

    def mtime
      node.mtime
    end

    def notfound
      env.delete :view
      format = selectFormat
      body = case format                                    # response body
             when /html/                                    # serialize HTML
               htmlDocument treeFromGraph.update({'#request'=>env})
             when /atom|rss|xml/                            # serialize Atom/RSS
               feedDocument treeFromGraph
             else                                           # serialize RDF
               if env[:repository] && writer = RDF::Writer.for(content_type: format)
                 env[:repository].dump writer.to_sym, base_uri: self
               else
                 ''
               end
             end
      [404, {'Content-Type' => format}, head? ? nil : [body]]
    end

    def offline?
      ENV.has_key?('OFFLINE') || env.has_key?(:offline)
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

    # Hash → querystring
    def HTTP.qs h
      return '?' unless h
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
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

    def unproxy schemeless = false
      r = [schemeless ? ['https:/', path] : path[1..-1],    # path → URI
           query ? ['?', query] : nil].join.R env

      r.host = r.host.downcase if r.host.match? /[A-Z]/     # normalize host capitalization
      env[:base] = r.uri.R env                              # update base URI
      r                                                     # unproxied URI
    end
  end

  include HTTP
end
