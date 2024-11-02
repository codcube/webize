module Webize
  module MIME

    # (MIME, data) -> RDF::Repository
    def readRDF format, content
      repository = RDF::Repository.new.extend Webize::Cache # instantiate repository with our added behaviours (TODO subclass vs extend? IIRC we had weird bugs where third-party/stdlib embeded-triplrs didn't think our subclass was a Repo due to strict equiv)

      case format                                                 # content type
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
          base = r.base_uri                                       # graph URI after any declarations

          # it is obviously up to handlers (caller) to do what they wish with this data,
          # though since we have doc/graph base URIs this is a good place to setup a skeleton
          # of reference for a basic "in->out" flow, if no further processing is needed
          # remember: no reference = no visibility. it may as well not exist!

          # the built-in non-RDF triplrs exploit this heavily when summarizing/merging/indexing

          # on the other hand,
          # Turtle is our default internal (compiled-output-graph/cache/storage) format, with a "static web server" mindset
          # of minimal processing. so little that without this, data won't appear in the output graph
          if format == 'text/turtle'
            repository << RDF::Statement.new(env[:base], RDF::URI(Contains), base) # request base 👉 this graph
            repository.each_subject.map{|s|                                      # this graph 👉 its subjects
              repository << RDF::Statement.new(base, RDF::URI(Contains), s) unless s.node?}
          end

          #repository.each_graph.map{|g|                                          # this graph 👉 additional named graphs
          #repository << RDF::Statement.new(base, RDF::URI(Contains), g.name) if g.name}

        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      repository
    end
  end
end
