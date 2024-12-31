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

          # emit pointers to graphs in RDF, as Ruby methods on Reader/Repo instances are out-of-band techniques from perspective of graph-data - even if we're still consuming data in this Ruby process, reader w/ declaratively updated base-URI falls out of scope when this method returns, and the named-graph tags available in the Repo instance aren't serializable into all popular formats, or preserved through many of our merge-oriented algorithms for collation/view purposes
          [r.base_uri,
           *graph.each_graph.map(&:name)].map do |_|
            (Resource _).graph_pointer graph
          end

        else
          logger.warn ["⚠️ no RDF reader for " , format].join
        end
      end

      graph
    end
  end
end
