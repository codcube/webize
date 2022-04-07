# coding: utf-8

class WebResource
  module Gemini

    include URIs

    def fetchGemini
      require 'net/gemini'
      response = Net::Gemini.get_response URI uri
      head = response.header
      body = response.body

      if format = {'.gmi' => 'text/gemini', '.ico' => 'image/png'}[path && File.extname(basename)] || head[:mimetype]
        format.downcase!
        env[:origin_format] = format           # record upstream format for log
        fixed_format = format.match? FixedFormat

        file = fsPath                          # cache storage
        if file[-1] == '/'                     # directory URI
          file += 'index'
        elsif directory?                       # directory missing /
          file += '/index'
        end

        POSIX.container file                   # containing dir(s)
        File.open(file, 'w'){|f| f << body }   # update cache

        if reader = RDF::Reader.for(content_type: format)
          env[:repository] ||= RDF::Repository.new
          reader.new(body, base_uri: self){|g|env[:repository] << g}
        else
          puts "⚠️ no RDF reader for #{format}" # ⚠️ undefined Reader
        end
        saveRDF
      else
        puts "⚠️ format undefined on #{uri}"    # ⚠️ undefined format
      end

      if env[:notransform] || fixed_format     # static content
        head = {'Content-Type' => format,      # response header
                'Content-Length' => body.bytesize.to_s}
        head['Expires']=(Time.now+3e7).httpdate if fixed_format # cache static assets
        [200, head, [body]]                    # response in upstream format
      else                                     # content-negotiated transform
        graphResponse format                   # response in preferred format
      end
    rescue Exception => e
      puts e.class, e.message, e.backtrace
      cacheResponse
    end
  end

  include Gemini
end
