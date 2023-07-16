# coding: utf-8

module Webize
  module Gemini

    def fetchGemini
      require 'net/gemini'
      response = Net::Gemini.get_response URI uri
      head = response.header
      body = response.body
      repository = RDF::Repository.new

      if format = {'.gmi' => 'text/gemini', '.ico' => 'image/png'}[path && File.extname(basename)] || head[:mimetype]
        format.downcase!
        env[:origin_format] = format             # record upstream format for log
        fixed_format = format.match? FixedFormat
        File.open(document, 'w'){|f| f << body } # update cache

        if reader = RDF::Reader.for(content_type: format)
          reader.new(body, base_uri: self){|g|repository << g}
        else
          logger.warn "⚠️ no RDF reader for #{format}" # ⚠️ undefined Reader
        end
      else
        logger.warn "⚠️ format undefined on #{uri}"    # ⚠️ undefined format
      end

      if env[:notransform] || fixed_format # static content
        head = {'Content-Type' => format,  # response header
                'Content-Length' => body.bytesize.to_s}
        head['Expires'] = (Time.now+3e7).httpdate if fixed_format # cache expiry
        [200, head, [body]]                # response in upstream format
      else                                 # content-negotiated transform
        respond [repository], format       # response in preferred format
      end
    rescue Exception => e
      logger.failure self, e
      fetchLocal
    end
  end

end
