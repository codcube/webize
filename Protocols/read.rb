module Webize
  module MIME

    # (MIME, data) -> RDF::Repository
    def readRDF format, content
      repository = RDF::Repository.new.extend Webize::Cache       # instantiate repository with our added behaviours (TODO subclass vs extend? IIRC we had some weird bugs where third-party/stdlib embeded-triplrs didn't think our subclass was a Repo due to strict equiv)

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

          r = reader.new(content, base_uri: self){|_|             # instantiate reader and reference it
            repository << _ }                                     # raw data -> RDF

          base = r.base_uri                                       # graph URI - declaratively settable, defaults to doc URI
          repository << RDF::Statement.new(env[:base], RDF::URI(Contains), self) # env 👉 doc
          repository << RDF::Statement.new(env[:base], RDF::URI(Contains), base) # env 👉 graph
          repository.each_graph.map{|g|                                        # graph 👉 additional graph(s)
            repository << RDF::Statement.new(base, RDF::URI(Contains), g.name) if g.name}
          repository.each_subject.map{|s|                                      # graph 👉 subjects
            repository << RDF::Statement.new(base, RDF::URI(Contains), s) unless s.node?} if format == 'text/turtle'
        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      repository
    end
  end
end
