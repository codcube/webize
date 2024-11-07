module Webize
  module MIME

    # (MIME, data) -> RDF::Repository
    def readRDF format, content
      repository = RDF::Repository.new.extend Webize::Cache # instantiate repository, add our behaviours
      # TODO revisit subclass vs extend. IIRC we had weird bugs where third-party/stdlib embeded-triplrs didn't think our subclass was a Repo due to strict equivalence

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
          base = r.base_uri                                       # graph URI. defaults to doc URI, declaratively updatable

          # the first stage of reading data, from arbitrary MIME format to RDF triples, is now done

          # now we add pointers to this graph from the base graph

          # our inlining and native data API requires these pointers as bridges of connectivity,
          # as in https://en.wikipedia.org/wiki/Seven_Bridges_of_K%C3%B6nigsberg

          # the reachability requirement allows implementation simplicity and better user/developer experience:

          # developer isn't handed soup of unconnected nodes, disjoint subgraphs, left to figure out
          # how to query it with SPARQL or even what RDF is entirely. the second-stage read (inlining) outputs:

          # native values with familiar Hash-accessor syntax-sugar, utility methods and JSON compatibility

          # we only 👉 graphs, not their nodes, to allow experts implementation flexibility on the latter:

          # - reachability = set-inclusion/inlining/visibility optimizations
          # - summary/merge/index/query operations without a mandatory subtractive pruning afterwards

          repository << RDF::Statement.new(env[:base], RDF::URI(Contains), base) # env graph 👉 doc graph
          repository.each_graph.map{|g|                                          # doc graph 👉 graph(s)
            repository << RDF::Statement.new(base, RDF::URI(Contains), g.name) if g.name}

          if format == 'text/turtle' # native RDF
            repository.each_subject.map{|s|                                      # doc graph 👉 node(s)
              repository << RDF::Statement.new(base, RDF::URI(Contains), s) unless s.node?}
          end # else: node 👉 delegated to non-RDF Reader implementation

        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      repository
    end
  end
end
