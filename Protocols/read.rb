module Webize
  module MIME

    # (MIME, data) -> RDF::Repository
    def readRDF format, content
      #puts [:read, uri].join ' '

      graph = RDF::Repository.new.extend Webize::Cache # instantiate repository extended with file-cache behaviours
      # TODO revisit subclass vs extend. we had issues where third-party code didn't think our subclass was a Repo due to strict equivalence or suchlike

      case format                                         # content type
      when /octet.stream/                                 #  blob
      when /^audio/                                       #  audio
        audio_triples graph
      when /^image/                                       #  image
        graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Image))
      when /^video/                                       #  video
        graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Video))
      else
        if reader = RDF::Reader.for(content_type: format) # if reader exists for format:

          # instantiate reader, bind it to a var, read data as RDF
          r = reader.new(content, base_uri: self){|_| graph << _ }

          # create first-class RDF statements of declaratively-updatable graph URI(s) as they are only otherwise available via out-of-band (from data-consumer perspective) methods in the Reader and Repository classes, the former also falling out of scope after this method returns
          (Resource r.base_uri).graph_pointer graph            # canonical graph URI
          graph.each_graph.map(&:name).compact.uniq.map do |g| # additional named-graph URIs
            g = Resource g
            graph << RDF::Statement.new(self, RDF::URI(Prov+'graph'), g)
            graph << RDF::Statement.new(g, RDF::URI(Link), RDF::URI('#' + g.local_id)) # graph 👉 representation
            g.graph_pointer graph
          end

        # (graph 👉 node) is provided in reader implementations. you can #dump a soup of disconnected subgraphs with the Turtle serializer, but these references improve book-keeping, discoverability, and making the HTML/JS UI more functional (automagic keyboard navigation) without any extra work beyond providing a reference skeleton

        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      graph
    end
  end
end
