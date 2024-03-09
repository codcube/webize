module Webize
  module MIME

    # local cache node URI -> data
    def read
      (File.open POSIX::Node(self).fsPath).read
    end

    # (MIME, data) -> RDF::Repository
    def readRDF format = fileMIME, content = read
      repository = RDF::Repository.new.extend Webize::Graph::Cache

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
          reader.new(content, base_uri: self){|_|repository << _} # read RDF

          if format == 'text/html' && reader != RDF::RDFa::Reader # read RDFa
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
