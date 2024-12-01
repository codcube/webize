module Webize
  module MIME

    # (MIME, data) -> RDF::Repository
    def readRDF format, content
      # first stage of reading data to our native graph structure: arbitrary MIME to RDF triples
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

          # 👉 loaded graph(s) from env/request base, for basic findability and reachability,
          # as in https://en.wikipedia.org/wiki/Seven_Bridges_of_K%C3%B6nigsberg

          # graph reader is responsible to 👉 nodes, to allow implementation flexibility:

          # - reachability = set-inclusion/inlining/visibility decisions
          # - summary/merge/index/query of graphs without a mandatory subtractive pruning stage

          repository << RDF::Statement.new(env[:base], RDF::URI(Contains), base) # 👉 graph
          repository.each_graph.map{|g|                                          # 👉 subgraph(s)
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
