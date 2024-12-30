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
      when /^video/                                               #  video
        repository << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Video))
      else
        if reader ||= RDF::Reader.for(content_type: format)       # if reader exists for format:
          #puts "read #{uri} as #{reader}"

          r = reader.new(content, base_uri: self){|_|             # instantiate reader
            repository << _ }                                     # raw data -> RDF

          graph = Resource r.base_uri                             # graph URI, declarable in document so this must be *after* the reader pass

          # add triples for the HTML view to render a bit more nicely or at all (reachability is required)
          # classic metaphor: https://en.wikipedia.org/wiki/Seven_Bridges_of_K%C3%B6nigsberg

          # related RDF formalisms and guidelines:
          # https://www.w3.org/submissions/CBD/ https://patterns.dataincubator.org/book/graph-per-source.html

          # base graph 👉 current graph through indirection of nested containing nodes
          container = graph.fsNames[0..-2].inject(base) do |parent, name| # walk from base to containing node
            c = RDF::URI('#container_' + Digest::SHA2.hexdigest(parent.to_s + name)) # container URI
            repository << RDF::Statement.new(parent, RDF::URI(Contains), c) # parent 👉 child container
            repository << RDF::Statement.new(c, RDF::URI(Title), name)      # container name
            c                                                               # container as parent in next iteration
          end

          repository << RDF::Statement.new(container, RDF::URI(Contains), graph) # container 👉 graph

          repository.each_graph.map{|g|                                          # graph 👉 named subgraph(s)
            repository << RDF::Statement.new(graph, RDF::URI(Contains), g.name) if g.name}

          if format == 'text/turtle'                                             # native RDF:
            repository.each_subject.map{|s|                                      # graph 👉 node(s)
              repository << RDF::Statement.new(graph, RDF::URI(Contains), s) unless s.node?}
          end                                                                    # non-RDF Reader emits 👉 node(s)
        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      repository
    end
  end
end
