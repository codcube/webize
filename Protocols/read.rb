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
        if reader ||= RDF::Reader.for(content_type: format)       # if reader exists for format:
          r = reader.new(content, base_uri: self){|_| repository << _ }            # read graph
          if self != r.base_uri                                                    # base URI override by document declaration?
            repository << RDF::Statement.new(env[:base], RDF::URI(Contains), r.base_uri) # reference graph base from canonical base
          end
        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      repository
    end
  end
end
