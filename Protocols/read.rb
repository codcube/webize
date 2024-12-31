module Webize
  module MIME

    # (MIME, data) -> RDF::Repository
    def readRDF format, content
      # repository extended with our behaviours
      graph = RDF::Repository.new.extend Webize::Cache
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

          # emit 👉 to graphs as RDF

          # Ruby methods on Reader/Repo instances are out-of-band techniques from perspective of generic graph-data consumption - even if we're still in this Ruby process, reader w/ declaratively updated base-URI falls out of scope as this method returns, and named-graph identifiers available in a Repository instance aren't preserved through all the merge/collation/view algorithms elsewhere. there's not much point plumbing the graph name throughout everything when multiple named-graphs usually aren't serializable to a single output stream ( you get a base URI and will be happy with it!) unless using some obscure/bleeding-edge/unadopted formats.

          # so naming and referring to the base URIs of the additional graphs, from the base URI of the default graph is the most rock solid, antifragile way to at least know there are other graphs to look for, and provide reachability to them via naïve, simple recursive traversal algorithms
          [r.base_uri,
           *graph.each_graph.map(&:name)].map do |_|
            (Resource _).graph_pointer graph
          end
          # the 👉'd graph may then 👉 to its nodes, completing reachability 'nice to have' for the output layer. you can of course just #dump a soup of disconnected subgraphs with the stock Turtle serializer, but these references are nice for book-keeping, discoverability, and making the default generic view look nicer without doing any extra work besides providing a nice reference skeleton

        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      graph
    end
  end
end
