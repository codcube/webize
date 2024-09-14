module Webize
  module MIME

    def read
      if file?
        readFile
      elsif directory?
        readDir
      end
    end

    def readStorage
      (File.open POSIX::Node(self).fsPath).read # TODO read from blob-store, mem-cache etc
    end

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

          # base URI can be updated by in-band declarations in document
          #puts [:req_base, env[:base], :doc_base, self, :base, r.base_uri].join " " unless self == r.base_uri
          repository << RDF::Statement.new(env[:base], RDF::URI(Contains), r.base_uri) unless env[:base] == r.base_uri # containment triple

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
