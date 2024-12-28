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
          #puts "read #{uri} as #{reader}"

          r = reader.new(content, base_uri: self){|_|             # instantiate reader
            repository << _ }                                     # raw data -> RDF

          graph = r.base_uri                                      # graph URI, declarable inside document so this is *after* the read
          hostname = graph.host || 'localhost'
          host = Webize::URI '//' + hostname                      # graph host

          # 👉 graphs grouped by host from base URI, for findability and reachability
          # as in https://en.wikipedia.org/wiki/Seven_Bridges_of_K%C3%B6nigsberg

          repository << RDF::Statement.new(env[:base], RDF::URI(Contains), host) # base 👉 host
          repository << RDF::Statement.new(host, RDF::URI(Contains), graph)      # host 👉 graph
          repository << RDF::Statement.new(host, RDF::URI(Title), hostname)

          repository.each_graph.map{|g|                                          # graph 👉 named subgraph(s)
            repository << RDF::Statement.new(graph, RDF::URI(Contains), g.name) if g.name}

          if format == 'text/turtle' # native RDF
            repository.each_subject.map{|s|                                      # graph 👉 node(s)
              repository << RDF::Statement.new(graph, RDF::URI(Contains), s) unless s.node?}
          end # non-RDF reader graph(s) 👉 nodes, allowing implementation flexibility:
          # * reachability = set-inclusion/inlining/output-visibility decisions
          # * summary/merge/index/query of graphs without requiring a subtractive pruning stage

        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      repository
    end
  end
end
