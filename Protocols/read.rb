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
          base = r.base_uri                                       # graph URI

          # RDF serializers may emit a soup of unconnected nodes, disjoint subgraphs etc
          # our serializers start at the base URI specified in the environment vars,
          # which means: no node reachability from base = no visibility on output

          # analogy: https://en.wikipedia.org/wiki/Seven_Bridges_of_K%C3%B6nigsberg

          # one may read much more data in than ends up in an output result/response graph
          # there's not a subtractive mandatory pruning in summary/merge/index/query operations,
          # but an additive 'explicitly include (make reachable) nodes' process begun below,
          # after the base URI (declaratively updatable) is found in the reader:

          repository << RDF::Statement.new(env[:base], RDF::URI(Contains), base) # env graph 👉 doc graph
          repository.each_graph.map{|g|                                          # doc graph 👉 graph(s)
            repository << RDF::Statement.new(base, RDF::URI(Contains), g.name) if g.name}

          if format == 'text/turtle' # RDF Reader
            repository.each_subject.map{|s|                                      # doc graph 👉 node(s)
              repository << RDF::Statement.new(base, RDF::URI(Contains), s) unless s.node?}
          end # else: node references emitted by non-RDF Reader

        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      repository
    end
  end
end
