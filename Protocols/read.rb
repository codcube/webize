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
          r = reader.new(content, base_uri: self){|_|repository << _} # read RDF

          # note: base URI may change due to document declarations
          repository << RDF::Statement.new(env[:base], RDF::URI(Contains), r.base_uri) unless r.base_uri == env[:base] # reference non-canonical base from canonical base

          if r.respond_to?(:read_RDFa?) && r.read_RDFa? # read RDFa
            begin
              RDF::RDFa::Reader.new(content, base_uri: self){|g|
                g.each_statement{|statement|
                  if predicate = Webize::MetaMap[statement.predicate.to_s]
                    next if predicate == :drop
                    statement.predicate = RDF::URI(predicate)
                  end
                  repository << statement
                }}
            rescue
              (logger.debug "⚠️ RDFa::Reader failed on #{uri}")
            end
          end
        else
          logger.warn ["⚠️ no RDF reader for " , format].join # reader not found
        end
      end

      repository
    end
  end
end
