%w(async async/barrier async/semaphore brotli cgi digest/sha2 open-uri rack resolv).map{|_| require _}

module Webize
  module HTTP
    Args = Webize.configList 'HTTP/arguments'            # permitted query arguments
    Methods = Webize.configList 'HTTP/methods'           # permitted HTTP methods
    ActionIcon = Webize.configHash 'style/icons/action'  # HTTP method -> char
    StatusIcon = Webize.configHash 'style/icons/status'  # status code (string) -> char
    StatusIcon.keys.map{|s|                              # status code (int) -> char
      StatusIcon[s.to_i] = StatusIcon[s]}
    Redirector = {}                                      # runtime redirection cache - NOTE we're going to switch to a per-process RDF::Repository for all metadata caching, soonish
    Referer = {}                                         # runtime referer cache

    # HTTP schema https://www.w3.org/2011/http

    def self.bwPrint(kv) = kv.map{|k,v| "\e[38;5;7;7m#{k}\e[0m#{v}\n"}

    # instantiate resource, call method and log response
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

    def self.debug? = ENV['CONSOLE_LEVEL'] == 'debug'

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

    # initial environment struct
    def self.env = {
      feeds: [],
      fragments: {},
      links: {},
      qs: {},
      warnings: []}

    # Node constructor method
    def self.Node(uri, env) = Node.new(uri).env env

  end
  class HTTP::Node < Resource
    include MIME

    # host adaptation runs on last (origin facing) proxy in chain
    def adapt? = !ENV.has_key?('http_proxy')

    def block domain
      File.open([Webize::ConfigPath, :blocklist, :domain].join('/'), 'a'){|list|
        list << domain << "\n"} # add to blocklist
      URI.blocklist             # read blocklist
      [302, {'Location' => Node(['//', domain].join).href}, []]
    end

    def clientETags
      return [] unless env.has_key? 'HTTP_IF_NONE_MATCH'
      env['HTTP_IF_NONE_MATCH'].strip.split /\s*,\s*/
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

      # convert search term to glob pattern
      pattern = ['*/' * hdepth,                       # glob less-significant (sub)slices in slice
                 globbed ? nil : '*', ps[1],          # globify slug if bare
                 globbed ? nil : '*'] if ps.size == 2 # .. if slug provided

      qs = ['?', env['QUERY_STRING']] if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?

      [302,{'Location' => [loc, pattern, qs].join},[]] # redirect to date-dir
    end

    def debug? = ENV['CONSOLE_LEVEL'] == 'debug'

    def deny status = 403, type = nil
      env[:deny] = true 
      env[:warnings].push({_: :a,
                           id: :allow,
                           title: 'allow temporarily',
                           style: 'font-size: 3em',
                           href: Node(['//', host, path, '?allow=', allow_key].join).href,
                           c: :👁️})

      if uri.match? Gunk

        hilite = '<span style="font-size:1.2em; font-weight: bold; background-color: #f00; color: #fff">'
        unhilite = '</span>'

        if query&.match? Gunk # drop query
          env[:warnings].push ['pattern block in query:<br>',
                               {_: :a,
                                id: :noquery,
                                title: 'URI without query',
                                href: Node(['//', host, path].join).href,
                                c: [host, path], style: 'background-color: #000; color: #fff'},
                               '?',
                               query.gsub(Gunk){|m|
                                 [hilite, m, unhilite].join }]
        else
          env[:warnings].push ['pattern block in URI:<br>',
                               uri.gsub(Gunk){|m|
                                 [hilite, m, unhilite].join}]
        end

        env[:warnings].push({_: :dl, # key/val view of query args
                             c: query_values.map{|k, v|
                               vs = v.class == Array ? v : [v]
                               [{_: :dt, c: HTML.markup(k, env)},
                                vs.map{|v|
                                  {_: :dd, c: HTML.markup(v.match(/^http/) ? RDF::URI(v) : v, env)} if v
                                }]}}) if query
      end

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
                        ['text/html; charset=utf-8', RDF::Repository.new.dump(:html, base_uri: self)]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => origin,
        'Content-Type' => type},
       head? ? [] : [content]]
    end

    # navigation pointers in HTTP metadata
    def dirMeta
      root = !path || path == '/'
      if host && root # up to parent domain
        env[:links][:up] = '//' + host.split('.')[1..-1].join('.')
      elsif !root     # up to parent path
        env[:links][:up] = [File.dirname(env['REQUEST_PATH']), '/', (env['QUERY_STRING'] && !env['QUERY_STRING'].empty?) ? ['?',env['QUERY_STRING']] : nil].join
      end             # down to children
      env[:links][:down] = '*' if (!host || offline?) && dirURI?
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
    def fetch nodes = nil
      return fetchLocal nodes if offline? # local node(s) - offline cache
      return fileResponse if immutable?   # local node - immutable cache
      return fetchAsync nodes if nodes    # remote node(s)
             fetchRemote                  # remote node
    end

    def fetchAsync nodes
      barrier = Async::Barrier.new
      semaphore = Async::Semaphore.new(16, parent: barrier)
      repos = []
      nodes.map{|n|
        semaphore.async{
          repos << (Node(n).fetchRemote thru: false)}}
      barrier.wait
      respond repos
    end

    # fetch resource and cache upstream/original and derived graph data
    # yes this is big, much of it to deal with the mess in the wild with MIME/charset data only inside the document,
    # rather than HTTP headers, requiring readahead sniffing. and normalizing name symbols to be what's in Ruby's list,
    # and fixing erroneous MIMEs and file extensions that won't map back to the right MIME if stored at upstream-derived path, and dealing with
    # the slightly odd choice of Exception handling flow being used for common HTTP Response statuses, and supporting conneg aware or unaware,
    # and proxy-mode (thru) fetches vs data-only fetches for aggregation/merging scenarios. add some hints for the renderer and logger,
    # and cache all the things. maybe we can split it all up somehow, especially so we can try other HTTP libraries more easily.

    URI_OPEN_OPTS = {open_timeout: 16,
                     read_timeout: 32,
                     redirect: false} # don't have HTTP library invisibly follow redirects. we use this data to make clients/servers/proxies relocation aware

    def fetchHTTP thru: true                                           # thread origin HTTP response through to caller?
      start_time = Time.now                                            # start "wall clock" timer for basic stats (fishing out super-slow stuff from aggregate fetches for optimization/profiling)
      doc = storage.document                                           # cache locator
      meta = [doc, '.meta'].join                                       # metadata locator
      cache_headers = {}
      if File.exist? meta
        metadata = ::JSON.parse File.open(meta).read
        cache_headers['If-None-Match'] = metadata['ETag'] if metadata['ETag']
        cache_headers['If-Modified-Since'] = metadata['Last-Modified'] if metadata['Last-Modified']
      end
      ::URI.open(uri, headers.merge(URI_OPEN_OPTS).merge(cache_headers)) do |response|
        fetch_time = Time.now                                          # fetch timing
        h = headers response.meta                                      # response header
        case status = response.status[0].to_i                          # response status
        when 204                                                       # no upstream content
          fetchLocal
        when 206                                                       # partial upstream content
          h['Access-Control-Allow-Origin'] ||= origin
          [206, h, [response.read]]
        else                                                           # massage metadata, cache and return data
          body = HTTP.decompress h, response.read                      # decompress body
          sha2 = Digest::SHA2.hexdigest body                           # hash body
          File.open(meta, 'w'){|f| f << h.merge({uri: uri, SHA2: sha2}).to_json} # cache metadata
          format = if (parts[0] == 'feed' || (Feed::Names.member? basename)) && adapt?
                     'application/atom+xml'                            # format defined on feed URI
                   elsif content_type = h['Content-Type']              # format defined in HTTP header
                     ct = content_type.split(/;/)
                     if ct.size == 2 && ct[1].index('charset')         # charset defined in HTTP header
                       charset = ct[1].sub(/.*charset=/i,'')
                       charset = nil if charset.empty? || charset == 'empty'
                     end
                     ct[0]
                   elsif path && content_type = (MIME.fromSuffix File.extname path)
                     content_type                                       # format defined on basename
                   else
                     'text/plain'
                   end.downcase                                         # normalize format
          if !charset && format.index('html') && metatag = body[0..4096].encode('UTF-8', undef: :replace, invalid: :replace).match(/<meta[^>]+charset=['"]?([^'">]+)/i)
            charset = metatag[1]                                        # detect in-band charset definition
          end
          charset = charset ? (normalize_charset charset) : 'UTF-8'     # normalize charset identifier
          body.encode! 'UTF-8', charset, invalid: :replace, undef: :replace if format.match? /(ht|x)ml|script|text/ # transcode to UTF-8
          format = 'text/html' if format == 'application/xml' && body[0..2048].match?(/(<|DOCTYPE )html/i) # HTML served as XML

          if (formats = RDF::Format.content_types[format]) &&           # content type
             (extensions = formats.map(&:file_extension).flatten) &&    # suffixes for content type
             !extensions.member?((File.extname(doc)[1..-1]||'').to_sym) # upstream suffix in mapped set?
            doc = [(link = doc), '.', extensions[0]].join               # append valid suffix. invalid path becomes link source for findability
            FileUtils.ln_s File.basename(doc), link unless dirURI? || File.exist?(link) || File.symlink?(link) # link upstream path to local path
          end

          File.open(doc, 'w'){|f|                                       # update cache
            f << (format == 'text/html' ? (HTML.cachestamp body, self) : body) } # set cache metadata in body if HTML

          if h['Last-Modified']                                         # set timestamp on filesystem
            mtime = Time.httpdate h['Last-Modified'] rescue nil
            FileUtils.touch doc, mtime: mtime if mtime
          end

          repository = (readRDF format, body).persist env               # read RDF and update cache
          repository << RDF::Statement.new(self, RDF::URI('#httpStatus'), status) unless status==200 # HTTP status in RDF
          repository << RDF::Statement.new(self, RDF::URI('#format'), format) # format
          repository << RDF::Statement.new(self, RDF::URI('#fTime'), fetch_time - start_time) # fetch time (wall clock)
          repository << RDF::Statement.new(self, RDF::URI('#pTime'), Time.now - fetch_time)   # parse/cache time (wall clock)

          if !thru
            print MIME.format_icon format
            repository                                                  # response graph w/o HTTP wrapping
          elsif env[:notransform] || format.match?(FixedFormat)
            staticResponse format, body                                 # HTTP response in upstream format
          else
            env[:origin_format] = format                                # note original format for logging/stats
            respond [repository], format                                # HTTP response in content-negotiated format
          end
        end
      end
    rescue Exception => e
      raise unless e.respond_to?(:io) && e.io.respond_to?(:status) # raise non-HTTP-response errors
      status = e.io.status[0].to_i                          # status
      repository ||= RDF::Repository.new
      repository << RDF::Statement.new(self, RDF::URI('#httpStatus'), status) # HTTP status in RDF
      head = headers e.io.meta                              # headers
      case status.to_s
      when /30[12378]/                                      # redirects
        location = e.io.meta['location']
        dest = Node join location
        if !thru                                            # notify on console and warnings-bar of new location
          logger.warn "➡️ #{uri} → #{location}"
          env[:warnings].push [{_: :a, href: href, c: uri}, '➡️',
                               {_: :a, href: dest.href, c: dest.uri}, '<br>']
        elsif no_scheme == dest.no_scheme
          if scheme == 'https' && dest.scheme == 'http'     # 🔒downgrade redirect
            logger.warn "🛑 downgrade redirect #{dest}"
            fetchLocal if thru
          elsif scheme == 'http' && dest.scheme == 'https'  # 🔒upgrade redirect
            logger.debug "🔒 upgrade redirect #{dest}"
            dest.fetchHTTP
          else                                              # redirect loop or non-HTTP protocol
            logger.warn "🛑 not following #{uri} → #{dest} redirect"
            fetchLocal if thru
          end
        else
          HTTP::Redirector[dest] ||= []                     # update redirection cache
          HTTP::Redirector[dest].push env[:base] unless HTTP::Redirector[dest].member? env[:base]
          [status, {'Location' => dest.href}, []]           # redirect
        end
      when /304/                                            # origin unmodified
        thru ? fetchLocal : repository
      when /300|[45]\d\d/                                   # not allowed/available/found
        body = HTTP.decompress(head, e.io.read).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        RDF::Reader.for(content_type: 'text/html').new(body, base_uri: self){|g|repository << g} if head['Content-Type']&.index 'html'
        head['Content-Length'] = body.bytesize.to_s
        if path == '/favicon.ico' && status / 100 == 4 # set default icon
          storage.write HTML::SiteIcon
          fileResponse
        elsif !thru
          repository
        elsif env[:notransform]
          [status, head, [body]] # static response data
        else
          env[:origin_status] = status
          respond [repository] # dynamic/transformable response data
        end
      else
        raise
      end
    end

    def fetchLocal nodes = nil
      return fileResponse if !nodes && storage.file? &&                    # static response if one non-transformable node
                             (format = fileMIME                            # lookup MIME type
                              env[:notransform] ||                         # (A → B) MIME transform and (A → A) intra-MIME reformat disabled by client
                                format.match?(MIME::FixedFormat) ||        # (A → B) MIME transform disabled by server
      (format == selectFormat(format) && !MIME::ReFormat.member?(format))) # (A → A) intra-MIME reformat disabled by server

      repos = (nodes || storage.nodes).map{|x|          # node(s) to fetch
        if x.file?                                      # file?
          x.file_triples x.readRDF                      # fetch filesystem metadata and file
        elsif x.directory?                              # directory?
          x.dir_triples RDF::Repository.new             # fetch directory metadata
        end}

      dirMeta                                           # 👉 container-adjacent nodes
      timeMeta unless host                              # 👉 timeslice-adjacent nodes

      respond repos                                     # response
    end

    def fetchRemote **opts
      start_time = Time.now
      env[:fetched] = true                              # denote network-fetch for logger
      case scheme                                       # request scheme
      when 'gemini'
        Gemini::Node.new(uri).env(env).fetch            # fetch w/ Gemini
      when /https?/
        if ENV.has_key?('http_proxy')
          insecure.fetchHTTP **opts                     # fetch w/ HTTP proxy
        else
          fetchHTTP **opts                              # fetch w/ HTTP(S)
        end
      else
        logger.warn "⚠️ unsupported scheme #{uri}"      # unsupported scheme
        opts[:thru] == false ? nil : notfound
      end
    rescue Exception => e                               # warn on exception
      env[:warnings].push [e.class,                     # error class
                           {_: :a, href: href, c: uri}, # error on URI
                           CGI.escapeHTML(e.message),   # error message
                           {_: :b, c: [:⏱️, Time.now - start_time, :s]}, '<br>']
      puts [:⚠️, uri,
            e.class, e.message,
            e.backtrace.join("\n")
           ].join ' '

      opts[:thru] == false ? nil : notfound
    end

    # unique identifier for file version. we want something that doesn't require reading and hashing the whole file,
    # though we SHA256 every file now so maybe switch to that, or if we switch to git for versioning, use its identifier
    def fileETag = Digest::SHA2.hexdigest [self,
                                           storage.mtime,
                                           storage.size].join

    def fileResponse = Rack::Files.new('.').serving(Rack::Request.new(env), storage.fsPath).yield_self{|s,h,b|
      return [s, h, b] if s == 304          # client cache is valid
      format = fileMIME                     # find MIME type - Rack's extension-map may differ from ours which preserves upstream/origin HTTP metadata
      h['content-type'] = format            # override Rack MIME type specification
      h['Expires'] = (Time.now + 3e7).httpdate if immutable? # give immutable node a long expiry
      [s, h, b]}
 
    def GET
      return hostGET if host                  # remote node
      ps = parts                              # parse path
      p = ps[0]                               # find first node in path
      return fetchLocal unless p              # local node - empty or root path
      return unproxy.hostGET if p[-1] == ':' && ps.size > 1        # remote node - proxy URI with scheme
      return unproxy.hostGET if p.index('.') && p != 'favicon.ico' # remote node - proxy URI sans scheme
      return dateDir if %w{m d h y}.member? p # redirect to current year/month/day/hour container
      return block parts[1] if p == 'block'   # block domain
      return fetch uris if extname == '.u' && query == 'fetch' # remote node(s) - enumerated in URI list
      fetchLocal                              # local node
    end

    def HEAD = self.GET.yield_self{|s, h, _|
                                   [s, h, []]} # status + header only

    def head? = env['REQUEST_METHOD'] == 'HEAD'

    # client<>proxy and internal headers not reused on proxy<>origin connection
    SingleHopHeaders = Webize.configTokens 'blocklist/header'

    # extensive header massaging happens here,
    # including restore HTTP RFC names from mangled CGI names - PRs pending for rack/falcon, maybe we can remove that part eventually
    def headers raw = nil
      raw ||= env || {}                               # raw headers
      head = {}                                       # cleaned headers
      logger.debug ["\e[7m raw headers 🥩🗣 \e[0m #{uri}\n", HTTP.bwPrint(raw)].join if debug? # raw debug-prints

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

      # accept graph data from origin even if client is oblivious
      #  ?notransform disables this, delivering upstream data-browser/UI code rather than graph data
      head['Accept'] = ['text/turtle', head['Accept']].join ',' unless env[:notransform] || head['Accept']&.match?(/text\/turtle/)

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

      head['User-Agent'] = 'curl/7.82.0' if %w(po.st t.co).member? host # prefer HTTP (HEAD) redirects over procedural Javascript - advertise a basic user-agent

      logger.debug ["\e[7m clean headers 🧽🗣 \e[0m #{uri}\n", HTTP.bwPrint(head)].join if debug? # clean debug-prints

      head
    end

    def hostGET
      return [301, {'Location' => relocate.href}, []] if relocate? # relocated node
      if path == '/feed' && adapt? && Feed::Subscriptions[host]    # aggregate feed node - doesn't exist on origin server
        return fetch Feed::Subscriptions[host]
      end
      dirMeta              # 👉 adjacent nodes
      return deny if deny? # blocked node
      fetch                # remote node
    end

    def immutable? = storage.file? && fileMIME.match?(FixedFormat)

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

    # instantiate node in current environment
    def Node(uri) = (HTTP::Node.new uri).env env

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
      env[:origin_status] = 404
      respond [RDF::Repository.new]
    end

    def origin
      if env['HTTP_ORIGIN']
        env['HTTP_ORIGIN']
      elsif env[:referer]
        ['http', host == 'localhost' ? '' : 's', '://', env[:referer].host].join
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

    # return graph in requested format
    def respond repositories, defaultFormat = 'text/html'
      format = selectFormat defaultFormat
      format += '; charset=utf-8' if %w{text/html text/turtle}.member? format

      # status code
      [env[:origin_status] || 200,

       # header
       {'Access-Control-Allow-Origin' => origin,
        'Content-Type' => format,
        'Last-Modified' => Time.now.httpdate,
        'Link' => linkHeader},

       # graph stats
       # count = out.size
       # out << RDF::Statement.new(dataset, RDF::URI(Size), count) unless count == 0                                # dataset size (triples)
       # if newest = query(timestamp).objects.sort[-1]                                                              # dataset timestamp
       #   out << RDF::Statement.new(dataset, RDF::URI(Date), newest)
       # end

       # body
       head? ? nil : [if writer = RDF::Writer.for(content_type: format)
                      writer.buffer(base_uri: self,
                                    prefixes: Prefixes) do |w|
                        repositories.map{|r|
                          w << r }
                      end
                     else
                       logger.warn "⚠️ Writer unavailable for #{format}" ; ''
                      end]]
    end

    def selectFormat default = nil                     # default-format argument
      default ||= 'text/html'                          # default when unspecified
      return default unless env.has_key? 'HTTP_ACCEPT' # no preference specified
      category = (default.split('/')[0] || '*') + '/*' # format-category wildcard symbol
      all = '*/*'                                      # any-format wildcard symbol

      index = {}                                       # build (q-value → format) index
      env['HTTP_ACCEPT'].split(/,/).map{|e|            # header values
        fmt, q = e.split /;/                           # (MIME, q-value) pair
        i = q && q.split(/=/)[1].to_f || 1             # default q-value
        index[i] ||= []                                # q-value entry
        index[i].push fmt.strip}                       # insert format at q-value

      index.sort.reverse.map{|_, accepted|             # search in descending q-value order
        return default if accepted.member? all         # anything accepted here
        return default if accepted.member? category    # category accepted here
        accepted.map{|format|
          return format if RDF::Writer.for(:content_type => format) || # RDF writer available for format
             ['application/atom+xml','text/html'].member?(format)}}    # non-RDF writer available
      default                                          # default format
    end

    def staticResponse format, body
      head = {'Content-Type' => format,                # response header
              'Content-Length' => body.bytesize.to_s,
             'Expires' => (Time.now + 3e7).httpdate}

      [200, head, [body]]                              # response
    end

    def storage = POSIX::Node self, env

    # URI -> HTTP headers
    def timeMeta
      n = nil # next-page locator
      p = nil # prev-page locator

      # path components
      ps = parts # all parts
      dp = []    # datetime parts
      dp.push ps.shift.to_i while ps[0] && ps[0].match(/^[0-9]+$/)

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

      q = (env['QUERY_STRING'] && !env['QUERY_STRING'].empty?) ? ('?'+env['QUERY_STRING']) : ''

      env[:links][:up] = [nil, dp[0..-2].map{|n| '%02d' % n}, '*', ps].join('/') + q if dp.length > 1 && ps[-1] != '*' && ps[-1]&.match?(GlobChars)
      env[:links][:prev] = [p, ps].join('/') + q + '#prev' if p
      env[:links][:next] = [n, ps].join('/') + q + '#next' if n
    end

    # unproxy request/environment URLs
    def unproxy
      r = unproxyURI                                            # unproxied URI
      r.scheme ||= 'https'                                      # set default scheme
      r.host = r.host.downcase if r.host.match? /[A-Z]/         # normalize hostname
      env[:base] = Node r.uri                                   # update base URI
      if env[:referer] # update referer URI
        env[:referer] = env[:referer].unproxyURI
        env['HTTP_REFERER'] = env[:referer].to_s
      end
      r
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
      readRDF.query(RDF::Query::Pattern.new :s, RDF::URI(Contains), :o).objects
    end

  end
  Identifiable.push HTTP::Node
end
