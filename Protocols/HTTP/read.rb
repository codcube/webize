require 'zstd-ruby'
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
      when /zstd/i
        Zstd.decompress body
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
      return fileResponse if storage.file? &&  # cache hit if file and
                             fileMIME.match?(FixedFormat) && # fixed format: we can't or prefer not to rewrite via content-negotiation preferences
                             !basename.match?(/index/i)      # exclude compressed index-files from fixed-format list - pattern in distro pkg-cache

      # network
      return fetchRemotes nodes if nodes # node(s)
             fetchRemote                 # node
    end

    # fetch w/ HTTP remote resource and cache upstream/original and derived graph data
    # much of this code deals with the mess in the wild of MIME/charset and other metadata only available inside the document,
    # rather than HTTP headers, requiring readahead sniffing. add some normalizing of name symbols to be what's in Ruby's list,
    # fix erroneous MIMEs and file extensions that won't map back to the right MIME if stored at upstream-supplied path, and work with
    # the slightly odd choice of exception-handler flow being used for common HTTP Response statuses, while supporting conneg-unaware clients/servers,
    # and proxy-mode (thru) fetches vs data-only fetches in aggregation/merging scenarios. add some hints for the renderer and logger,
    # and cache all the things. maybe we can split this up somehow, especially so we can try other HTTP libraries more easily.

    URI_OPEN_OPTS = {open_timeout: 16,
                     read_timeout: 32,
                     redirect: false} # don't invisibly follow redirects in HTTP-library code, return this data to us and clients/proxies so they can update URL bars, source links on 301s etc

    def fetchHTTP thru: true                                           # thread upstream HTTP response through to caller, or simply return fetched data
      start_time = Time.now                                            # start "wall clock" timer for basic stats (fishing out super-slow stuff from aggregate fetches for optimization/profiling)

      doc = storage.document                                           # graph-cache location
      meta = [doc, '.meta'].join                                       # HTTP metadata-cache location

      cache_headers = {}                                               # conditional-request headers
      if File.exist? meta                                              # cached metadata (HEAD) for resource?
        metadata = ::JSON.parse File.open(meta).read                   # read metadata and set header fields
        cache_headers['If-None-Match'] = metadata['ETag'] if metadata['ETag']
        cache_headers['If-Modified-Since'] = metadata['Last-Modified'] if metadata['Last-Modified']
      end

      head = headers.                                                  # request headers
               merge(URI_OPEN_OPTS).                                   # configure open-URI
               merge(cache_headers)                                    # cache headers
                                                                       # accept graph data from origin when client is not content-negotiation aware
      head['Accept'] = ['text/turtle', head['Accept']].join ',' unless env[:notransform] || !head.has_key?('Accept') || head['Accept'].match?(/text\/turtle/)

      ::URI.open(uri, head) do |response|
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
          notransform = env[:notransform] || format.match?(FixedFormat) # transformable content?

          if ext = File.extname(doc)[1..-1]                             # name suffix
            ext = ext.to_sym
          end

          if (formats = RDF::Format.content_types[format]) &&           # content-type definitions
             !(exts = formats.map(&:file_extension).flatten).member?(ext) # valid suffix for content type?
            doc = [(link = doc), '.', exts[0]].join                       # append suffix, link from original name
            FileUtils.ln_s File.basename(doc), link unless File.exist?(link) || File.symlink?(link)
          end

          File.open(doc, 'w'){|f|f << body }                            # cache raw data

          if h['Last-Modified']                                         # preserve origin timestamp
            mtime = Time.httpdate h['Last-Modified'] rescue nil
            FileUtils.touch doc, mtime: mtime if mtime
          end

          unless thru && notransform
            graph = readRDF(format, body).persist env, self, updates: !thru # parse and cache graph data
          end

          if !thru                                                      # no HTTP response construction or proxy
            print MIME.format_icon format                               # denote fetch with single character for activity feedback
                                                                        # fetch statistics
            h = Resource '//' + host                                    # host URI
            h.graph_pointer graph                                       # per-host remote source listing
            graph << RDF::Statement.new(h, RDF::URI('#remote_source'), self) # source identity
            graph << RDF::Statement.new(self, RDF::URI(HT + 'status'), status) # HTTP status
            graph << RDF::Statement.new(self, RDF::URI('#fTime'), fetch_time - start_time) # fetch timing
            graph << RDF::Statement.new(self, RDF::URI('#pTime'), Time.now - fetch_time)   # parse/cache timing

            graph                                                       # return cached+fetched graph data
                                                                        # webizing proxy HTTP-through response
          elsif notransform                                             # origin/upstream-server format preference
            staticResponse format, body                                 # HTTP response in upstream format
          else                                                          # client format preference
            env[:origin_format] = format                                # note original format for logging/stats
            h.map{|k,v|                                                 # HTTP resource metadata to graph
              graph << RDF::Statement.new(self, RDF::URI(HT+k), v)} if graph
            respond [graph], format                                     # HTTP response in content-negotiated format
          end
        end
      end
    rescue Exception => e
      raise unless e.respond_to?(:io) && e.io.respond_to?(:status) # raise non-HTTP-response errors
      status = e.io.status[0].to_i                          # status
      repository ||= RDF::Repository.new
      repository << RDF::Statement.new(env[:base], RDF::URI('#remote_source'), self) # source provenance
      repository << RDF::Statement.new(self, RDF::URI(HT + 'status'), status) # HTTP status in RDF
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

    def fetchList
      return fetch uris if env[:qs].has_key?('fetch') # fetch each URI in list
      fetchLocal                                      # return list of URIs, no follow-on fetching
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
      repository << RDF::Statement.new(env[:base], RDF::URI('#remote_source'), self) # source provenance

      opts[:thru] == false ? repository : notfound
    end

    def fetchRemotes nodes
      barrier = Async::Barrier.new # limit concurrency
      semaphore = Async::Semaphore.new(16, parent: barrier)

      repos = []                   # repository references

      nodes.map{|n|
        semaphore.async{           # fetch URI -> repository
          repos << (Node(n).fetchRemote thru: false)}}

      barrier.wait
      respond repos                # repositories -> HTTP response
    end

    def GET
      return hostGET if host                                     # fetch remote node
      ps = parts                                                 # parse path
      p = ps[0]                                                  # find first path component

      return fetchLocal unless p                                 # fetch local node at null or root path

      return unproxy.hostGET if (p[-1] == ':' && ps.size > 1) || # fetch remote node at proxy-URI with scheme
                            (p.index('.') && p != 'favicon.ico') # fetch remote node at proxy-URI sans scheme

      return dateDir if %w{m d h y}.member? p                    # redirect to current year/month/day/hour container

      return block parts[1] if p == 'block'                      # add domain to blocklist

      return redirect '/d?f=msg*' if path == '/mail'             # redirect to email inbox (day-dir and FIND arg)

      return fetchList if extname == '.u'                        # fetch URIs in list

      fetchLocal                                                 # fetch local node
    rescue Exception => e
      env[:warnings].
        push({_: :pre,
              c: CGI.escapeHTML(
                [e.class,
                 e.message,
                 e.backtrace].join "\n")})
      env[:origin_status] = 500
      notfound
    end

    def HEAD = self.GET.yield_self{|s, h, _|
                                   [s, h, []]} # status + header only

    def hostGET
      return [301, {'Location' => relocate.href}, []] if relocate? # relocated node
      dirMeta              # 👉 adjacent nodes
      return deny if deny? # blocked node
      fetch                # remote node
    end

  end
end

