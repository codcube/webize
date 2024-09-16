module Webize
  module MIME

    # (MIME, data) -> RDF::Repository
    def readRDF format, content
      repository = RDF::Repository.new.extend Webize::Cache       # add repository behaviours to instance via #extend TODO subclass?

      case format                                                 # content type:TODO needless reads? stop media reads earlier
      when /octet.stream/                                         #  blob
      when /^audio/                                               #  audio
        audio_triples repository
      when /^image/                                               #  image
        repository << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Image))
        repository << RDF::Statement.new(self, RDF::URI(Title), basename)
      when /^video/                                               #  video
        repository << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Video))
        repository << RDF::Statement.new(self, RDF::URI(Title), basename)
      else
        if reader ||= RDF::Reader.for(content_type: format)       # find reader
          r = reader.new(content, base_uri: env[:base]){|_|       # create reader
            repository << _} # read RDF

          # base URI may be overriden by document declarations
          if env[:base] != r.base_uri
            # reference non-canonical base from canonical base
            repository << RDF::Statement.new(env[:base], RDF::URI(Contains), r.base_uri)
          end
        else
          logger.warn ["⚠️ no RDF reader for " , format].join # reader not found
        end
      end

      repository
    end
  end
end
