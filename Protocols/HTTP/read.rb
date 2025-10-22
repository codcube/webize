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
      Console.logger.warn head, e
      head['Content-Encoding'] = encoding
      body
    end
  end

  class HTTP::Node

    URI_OPEN_OPTS = {open_timeout: 8,
                     read_timeout: 30,
                     redirect: false} # don't invisibly follow redirects inside HTTP-library code

    # fetch resource representation and return it or derived graph-data or a representation thereof
    def fetchHTTP
      doc = storage.document                                   # graph-cache location
      meta = [doc, '.meta'].join                               # HTTP metadata-cache location

      cache_headers = {}                                       # conditional-request headers
      if File.exist? meta                                      # cached metadata (HEAD) for resource?
        metadata = ::JSON.parse File.open(meta).read           # read metadata and set header fields
        cache_headers['If-None-Match'] = metadata['ETag'] if metadata['ETag']
        cache_headers['If-Modified-Since'] = metadata['Last-Modified'] if metadata['Last-Modified']
      end

      head = headers.                                          # request headers
               merge(URI_OPEN_OPTS).                           # configure open-URI
               merge(cache_headers)                            # cache headers
                                                               # accept RDF from origin when our client is content-negotiation unaware
      head['Accept'] = ['text/turtle', head['Accept']].join ',' unless head['Accept']&.match?(/text\/turtle/)

      ::URI.open(uri, head) do |response|
        h = headers response.meta                              # response header
        case status = response.status[0].to_i                  # response status
        when 204                                               # no upstream content
          localGET
        when 206                                               # partial upstream content
          h['Access-Control-Allow-Origin'] ||= origin
          [206, h, [response.read]]
        else                                                   # massage metadata, cache and return data
          body = HTTP.decompress h, response.read              # decompress body
                                                               # cache HTTP metadata
          File.open(meta, 'w'){|f| f << h.merge({uri: uri}).to_json}

          format = if (parts[0] == 'feed' || (Feed::Names.member? basename)) && adapt?
                     'application/atom+xml'                    # format defined on feed URI
                   elsif content_type = h['Content-Type']      # format defined in HTTP header
                     ct = content_type.split(/;/)
                     if ct.size == 2 && ct[1].index('charset') # charset defined in HTTP header
                       charset = ct[1].sub(/.*charset=/i,'')
                       charset = nil if charset.empty? || charset == 'empty'
                     end
                     ct[0]
                   elsif path && content_type = (MIME.fromSuffix File.extname path)
                     content_type                              # format defined on basename
                   else
                     'text/plain'
                   end.downcase                                # normalize format

          if !charset && format.index('html') && metatag = body[0..4096].encode('UTF-8', undef: :replace, invalid: :replace).match(/<meta[^>]+charset=['"]?([^'">]+)/i)
            charset = metatag[1]                               # detect in-band charset definition
          end
          charset = charset ? (normalize_charset charset) : 'UTF-8' # normalize charset identifier

          body.encode! 'UTF-8', charset, invalid: :replace, undef: :replace if format.match? /(ht|x)ml|script|text/ # transcode to UTF-8
          body = HTML.cachestamp body, self if format == 'text/html' # stamp with in-band cache metadata

          format = 'text/html' if format == 'application/xml' && body[0..2048].match?(/(<|DOCTYPE )html/i) # detect (X)HTML served as XML

          if ext = File.extname(doc)[1..-1]                    # name suffix with stripped leading '.'
            ext = ext.to_sym                                   # symbolize for lookup in RDF::Format
          end
          if (mimes = RDF::Format.content_types[format]) &&    # MIME definitions
             !(exts = mimes.map(&:file_extension).flatten).member?(ext) # upstream extension doesn't map to MIME?
            doc = [(link = doc), '.', exts[0]].join            # memo original path and append mapped extension
            FileUtils.ln_s File.basename(doc), link unless !format.match?(FixedFormat) || # link original to updated path
                                                            File.exist?(link) ||
                                                            File.symlink?(link)
          end

          File.open(doc, 'w'){|f| f << body }                  # cache raw data
          graph = readRDF format, body                         # parse graph-data

          if h['Last-Modified']                                # cache origin timestamp
            mtime = Time.httpdate h['Last-Modified'] rescue nil
            FileUtils.touch doc, mtime: mtime if mtime
          end

          if block_given?                                      # caller to consume intermediate representation of fetch results
            yield graph                                        # yield fetched/webized representation (RDF::Graph)
            [status, h, nil]                                   # HTTP status and headers, no further handling of body
          elsif format.match? FixedFormat                      # fixed format: UNIMPLEMENTED transcode of static-asset formats. ffmpeg/imagemagick could produce e.g. JPG/PNG images for browsers not accepting AVIF/WEBP
            staticResponse format, body                        # HTTP response in origin format
          else                                                 # content-negotiated format:
            env[:origin_format] = format                       # memo origin format (for logger. TODO logger queries HTTP-request metadata available in graph)
            graph.index env, self                              # memo graph in local cache-storage / index-structures
            h.map{|k,v|                                        # memo origin resource metadata in graph
              graph << RDF::Statement.new(self, RDF::URI(HT+k), v)} if graph
            respond graph, format                              # HTTP response in content-negotiated format
          end
        end
      end
    rescue Exception => e
      raise unless e.respond_to?(:io) && e.io.respond_to?(:status) # raise non-HTTP-response errors
      status = e.io.status[0].to_i                         # source status
      head = headers e.io.meta                             # headers
      case status.to_s
      when /30[12378]/                                     # redirects
        location = e.io.meta['location']
        dest = Node join location
                                                           # note new location
        logger.warn "➡️ #{uri} → #{location}"
        env[:warnings].push [{_: :a, href: href, c: uri}, '➡️',
                             {_: :a, href: dest.href, c: dest.uri}, '<br>']

        if no_scheme == dest.no_scheme
          if scheme == 'https' && dest.scheme == 'http'    # 🔒downgrade redirect
            logger.warn "🛑 downgrade redirect #{dest}"
            localGET
          elsif scheme == 'http' && dest.scheme == 'https' # 🔒upgrade redirect
            logger.debug "🔒 upgrade redirect #{dest}"
            dest.fetchHTTP
          else                                             # redirect loop or non-HTTP protocol
            logger.warn "🛑 not following #{uri} → #{dest} redirect"
            localGET
          end
        else
          HTTP::Redirector[dest] ||= []                    # update redirection cache
          HTTP::Redirector[dest].push env[:base] unless HTTP::Redirector[dest].member? env[:base]
          [status, {'Location' => dest.href}, []]          # redirect
        end
      when /304/                                           # origin unmodified
        block_given? ? [304,{},[]] : localGET              # return unmodified-at-origin entity if requested
      when /300|[45]\d\d/                                  # not allowed/available/found
        body = HTTP.decompress(head, e.io.read).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        RDF::Reader.for(content_type: 'text/html').new(body, base_uri: self){|g|repository << g} if head['Content-Type']&.index 'html'
        head['Content-Length'] = body.bytesize.to_s
        if status == 403 # redirect to origin for anubis/cloudflare/etc challenges via upstream UI
          [302, {'Location' => uri}, []]
        elsif block_given?
          [status, head, body]
        else
          env[:origin_status] = status
          respond repository # dynamic/transformable response data
        end
      else
        raise
      end
    end

    def fetch **opts
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
        notfound
      end
    rescue Exception => e                               # warn on exception
      env[:warnings].push [e.class,                     # error class
                           {_: :a, href: href, c: uri}, # request URI
                           (CGI.escapeHTML e.message),  # error message
                           #{_: :pre,                    # error backtrace
                           #c: (CGI.escapeHTML e.backtrace.join "\n")}
                          ]
      notfound
    end

    def GET
      return peerGET if host                                     # fetch remote node
      ps = parts                                                 # parse path
      p = ps[0]                                                  # first path component
      return localGET unless p                                   # fetch local node (null or root path)
      return unproxy.peerGET if (p[-1] == ':' && ps.size > 1) || # fetch remote node (proxy-URI avec scheme)
                            (p.index('.') && p != 'favicon.ico') # fetch remote node (proxy-URI sans scheme)
      return dateDir if %w{m d h y}.member? p                    # redirect to current year/month/day/hour container
      return block parts[1] if p == 'block'                      # add domain to blocklist
      return redirect '/d?f=msg*' if path == '/mail'             # redirect to message inbox (day-dir with FIND invocation)
      localGET                                                   # fetch local node
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

    # GET local node
    def localGET
      if streaming?
        return firehose if path == '/feed'                                 # stream of local updates
        return multiGET uris if extname == '.u'                            # aggregated GET of node(s)
      end

      return fileResponse if storage.file? &&                              # static response if available and non-transformable:
                             (format = fileMIME                            #  lookup MIME type
                              env[:qs]['notransform'] ||                   #  (A → B) MIME transform blocked by client
                                format.match?(MIME::FixedFormat) ||        #  (A → B) MIME transform blocked by server
      (format == selectFormat(format) && !MIME::ReFormat.member?(format))) #  (A → A) MIME reformat blocked by server

      dirMeta                                                              # 👉 container-adjacent nodes
      timeMeta                                                             # 👉 timeslice-adjacent nodes

      pat = RDF::Query::Pattern.new self, :p, :o
      respond [Webize::Graph.query(pat),                                   # read transient and persisted graph data
               *storage.nodes.map(&:read)]                                 # return representation of local node(s)
    end

    # GET node from peer (origin server or chained proxy)
    def peerGET
      return [301, {'Location' => relocate.href}, []] if relocate?     # relocated node
      return deny if deny?                                             # block node access
      AllowHosts.push host if temp_allow? && !AllowHosts.member?(host) # allow node access

      # many clients and apps are unaware of content-negotiation facilities and become confused or fail if we return a differing-from-original format
      # we also don't want to incur origin-roundtrip HTTP Requests to see if content at a URI changed when it won't ever due to content-addressing
      # if storage name matches FixedFormat regex, no formats or origin-checks happen
      return fileResponse if storage.file? &&                # return cached node if exists,
                             fileMIME.match?(FixedFormat) && # and format is fixed,
                             !basename.match?(/index/i)      # unless conneg-enabled/cache-busted index file (ZIP/TAR'd distro package-lists, dynamic index images)

      dirMeta # 👉 adjacent nodes
      fetch   # fetch remote node
    end

  end
end

