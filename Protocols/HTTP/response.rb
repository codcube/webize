module Webize
  class HTTP::Node

    def block domain
      File.open([Webize::ConfigPath, :blocklist, :domain].join('/'), 'a'){|list|
        list << domain << "\n"} # add to blocklist
      URI.blocklist             # read blocklist
      redirect Node(['//', domain].join).href
    end


    def deny
      status = 403
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

      type, content = if ext == '.css'
                        ['text/css', '']
                      elsif fontURI?
                        ['font/woff2', HTML::SiteFont]
                      elsif imgURI?
                        ['image/png', HTML::SiteIcon]
                      elsif ext == '.js'
                        ['application/javascript', "// URI: #{uri.match(Gunk) || host}"]
                      elsif ext == '.json'
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
        redirect Node(['//', host, path].join).href
      end
    end

    def fileResponse = Rack::Files.new('.').serving(Rack::Request.new(env), storage.fsPath).yield_self{|s,h,b|
      return [s, h, b] if s == 304          # client cache is valid
      format = fileMIME                     # find MIME type - Rack's extension-map may differ from ours which preserves upstream/origin HTTP metadata
      h['content-type'] = format            # override Rack MIME type specification
      h['Expires'] = (Time.now + 3e7).httpdate if format.match?(FixedFormat) # give immutable cache a long expiry
      [s, h, b]}

    def hostGET
      return [301, {'Location' => relocate.href}, []] if relocate? # relocated node
      if path == '/feed' && adapt? && Feed::Subscriptions[host]    # aggregate feed node - doesn't exist on origin server
        return fetch Feed::Subscriptions[host]
      end
      dirMeta              # 👉 adjacent nodes
      return deny if deny? # blocked node
      fetch                # remote node
    end
 
    def notfound
      env[:origin_status] = 404
      respond [RDF::Repository.new]
    end

    def redirect(location) = [302, {'Location' => location}, []]

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

    def staticResponse format, body
      head = {'Content-Type' => format,                # response header
              'Content-Length' => body.bytesize.to_s,
             'Expires' => (Time.now + 3e7).httpdate}

      [200, head, [body]]                              # response
    end

  end
end
