module Webize
  class HTTP::Node

    def fileResponse = Rack::Files.new('.').serving(Rack::Request.new(env), storage.fsPath).yield_self{|s,h,b|
      return [s, h, b] if s == 304          # client cache is valid
      format = fileMIME                     # find MIME type - Rack's extension-map may differ from ours which preserves upstream/origin HTTP metadata
      h['content-type'] = format            # override Rack MIME type specification
      h['Expires'] = (Time.now + 3e7).httpdate if format.match?(FixedFormat) # give immutable cache a long expiry
      [s, h, b]}

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
