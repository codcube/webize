module Webize
  module HTTP

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

    # fetch node(s) from local or remote storage
    def fetch nodes = nil

      # local
      return fetchLocal nodes if offline? # offline
      return fileResponse if storage.file? && fileMIME.match?(FixedFormat) && !basename.match?(/index/i)# cache hit

      # network
      return fetchMany nodes if nodes # node(s)
             fetchRemote              # node
    end

    def fetchMany nodes
                         # limit concurrency
      barrier = Async::Barrier.new
      semaphore = Async::Semaphore.new(16, parent: barrier)

      repos = []         # repositories

      nodes.map{|n|
        semaphore.async{ # URI -> Repository
          repos << (Node(n).fetchRemote thru: false,
                                        summarize: nodes.size > 16)}}

      barrier.wait
      respond repos      # HTTP response
    end

    # fetch resource and cache upstream/original and derived graph data
    # much of this code deals with the mess in the wild of MIME/charset and other metadata only available inside the document,
    # rather than HTTP headers, requiring readahead sniffing. add some normalizing of name symbols to be what's in Ruby's list,
    # fix erroneous MIMEs and file extensions that won't map back to the right MIME if stored at upstream-supplied path, and work with
    # the slightly odd choice of exception-handler flow being used for common HTTP Response statuses, while supporting conneg-unaware clients/servers,
    # and proxy-mode (thru) fetches vs data-only fetches in aggregation/merging scenarios. add some hints for the renderer and logger,
    # and cache all the things. maybe we can split this up somehow, especially so we can try other HTTP libraries more easily.

    URI_OPEN_OPTS = {open_timeout: 16,
                     read_timeout: 32,
                     redirect: false} # don't invisibly follow redirects in HTTP-library code, return this data to us and clients/proxies so they can update URL bars, source links on 301s etc

    def fetchHTTP thru: true, summarize: false                         # return HTTP response to caller? summarize fetched content?
      start_time = Time.now                                            # start "wall clock" timer for basic stats (fishing out super-slow stuff from aggregate fetches for optimization/profiling)
      doc = storage.document                                           # graph-cache location
      meta = [doc, '.meta'].join                                       # HTTP metadata-cache location
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

          File.open(meta, 'w'){|f| f << h.merge({uri: uri}).to_json}   # cache HTTP metadata

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
          body = HTML.cachestamp body, self if format == 'text/html'    # stamp with in-band cache metadata

          format = 'text/html' if format == 'application/xml' && body[0..2048].match?(/(<|DOCTYPE )html/i) # allow (X)HTML to be served as XML

          if ext = File.extname(doc)[1..-1]                             # name suffix
            ext = ext.to_sym
          end

          if (formats = RDF::Format.content_types[format]) &&           # content-type definitions
             !(exts = formats.map(&:file_extension).flatten).member?(ext) # valid suffix for content type?
            doc = [(link = doc), '.', exts[0]].join                       # append suffix, link from original name
            FileUtils.ln_s File.basename(doc), link unless File.exist?(link) || File.symlink?(link)
          end

          File.open(doc, 'w'){|f|f << body }                            # cache fetched representation

          if h['Last-Modified']                                         # preserve origin timestamp
            mtime = Time.httpdate h['Last-Modified'] rescue nil
            FileUtils.touch doc, mtime: mtime if mtime
          end

          repository = (readRDF format, body).persist(env, summarize: summarize)  # read RDF and update cache
          repository << RDF::Statement.new(env[:base], RDF::URI('#source'), self) # source provenance
          repository << RDF::Statement.new(self, RDF::URI('#httpStatus'), status) # HTTP status in RDF
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
      repository << RDF::Statement.new(env[:base], RDF::URI('#source'), self) # source provenance
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
          repository
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
      nodes ||= storage.nodes                                              # default node set if unspecified
      repos = nodes.map &:read                                             # read node(s)
      dirMeta                                                              # 👉 container-adjacent nodes
      timeMeta                                                             # 👉 timeslice-adjacent nodes
      respond repos                                                        # response repository-set
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

      repository ||= RDF::Repository.new
      repository << RDF::Statement.new(env[:base], RDF::URI('#source'), self) # source provenance

      opts[:thru] == false ? repository : notfound
    end

    def GET
      return hostGET if host     # remote node

      ps = parts                 # path nodes
      p = ps[0]                  # first node

      return fetchLocal unless p # local node - void or root path
                                 # proxy URI
      return unproxy.hostGET if (p[-1] == ':' && ps.size > 1) || # remote node, URI w/ scheme
                                (p.index('.') && p != 'favicon.ico') #            sans scheme

      return dateDir if %w{m d h y}.member? p # current year/month/day/hour contents
      return block parts[1] if p == 'block'   # block domain
      return redirect '/d?f=msg*' if path == '/mail' # email

      if extname == '.u' # URI list
        case query
        when 'fetch'     # remote node(s)
          return fetch uris
        when 'load'      # cached node(s)
          return fetchLocal uris
        end
      end

      fetchLocal         # local node(s)
    end

    def HEAD = self.GET.yield_self{|s, h, _|
                                   [s, h, []]} # status + header only

    def hostGET
      return [301, {'Location' => relocate.href}, []] if relocate? # relocated node
      if path == '/feed' && adapt? && Feed::Subscriptions[host]    # aggregate feed node - doesn't exist on origin server
        return fetch Feed::Subscriptions[host]
      end
      dirMeta              # 👉 adjacent nodes
      return deny if deny? # blocked node
      fetch                # remote node
    end

  end
end

