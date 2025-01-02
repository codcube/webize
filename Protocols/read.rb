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

          # Ruby methods on Reader/Repo instances are out-of-band techniques from perspective of generic data consumption. even in this Ruby process, the reader w/ declaratively updated base-URI falls out of scope as this method returns, and named-graph identifiers available in a Repository instances aren't preserved through all our merge/collation/view algorithms elsewhere - there's not much point plumbing them through everything when multiple named-graphs oten aren't serializable to a single output stream (you will get a base URI definition and be happy!) unless using some bleeding-edge formats. we've taken a look at NQuads and RDFSTAR and the Ruby libraries have above average support for such things, but we're kind of luddites.

          # naming and referring to the URIs of the additional graphs from the graph URI of the base graph is one the most rock solid, antifragile ways to at least know there are other graphs to look for, and provide reachability to them via naïve, simple recursive traversal algorithms. we're mainly doing this so we can be lazy and have simpler implementations not need to stack #each_graph and some graph op all over the place
          [r.base_uri,
           *graph.each_graph.map(&:name)].uniq.map do |g|
            puts "graph #{g}"
            (Resource g).graph_pointer graph
          end

        # now the graph hsa the responsibility 👉 to its nodes if you're adding these 'nice to have' in-band references. you can of course just #dump a soup of disconnected subgraphs with the stock Turtle serializer, but these references are nice for book-keeping, discoverability, and making the default generic view more functional (automagic gopher-style navigation) without doing any extra work besides providing the reference skeleton

        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      graph
    end
  end
end
