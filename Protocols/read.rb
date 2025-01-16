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

          # Ruby methods on Reader/Reposittory are out-of-band (even inaccessible) techniques for generic data consuers. in this process, the reader w/ declaratively updated base-URI falls out of scope as this method returns, so here we 👉 graph URIs, for basic graph-name preservation and wayfinding:
          [r.base_uri,
           *graph.each_graph.map(&:name)].compact.uniq.map do |g|
            graph << RDF::Statement.new(self, RDF::URI(Prov+'graph'), g)
            (Resource g).graph_pointer graph
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
