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
          base = r.base_uri                                       # graph URI after any declarations

          # the graph needs a basic reference skeleton before output can commence
          # no reference reachability to/from base-URI = no visibility on output

          # example: https://en.wikipedia.org/wiki/Seven_Bridges_of_K%C3%B6nigsberg

          # this characteristic eliminates needs for pruning in summary/merge/index/query operations.
          # references to output nodes are added by the handlers, specific to the request needs

          # standard RDF serializers usually dump out a soup of maybe-unconnected nodes, disjoint subgraphs etc
          # add this skeleton when going from native RDF readers to our serializers

          if format == 'text/turtle' # our preferred native storage format
            repository << RDF::Statement.new(env[:base], RDF::URI(Contains), base) # request graph 👉 current graph
            repository.each_subject.map{|s|                                        # current graph 👉 subjects
              repository << RDF::Statement.new(base, RDF::URI(Contains), s) unless s.node?}
          end

          repository.each_graph.map{|g|                                            # current graph 👉 additional named graphs
          repository << RDF::Statement.new(base, RDF::URI(Contains), g.name) if g.name}

        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      repository
    end
  end
end
