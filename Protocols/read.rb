module Webize
  class Resource

    def graph_pointer graph
      # point to graph URI so it is findable / reachable in various traverse, recursive walk, index lookup algos throughout the code

      # the classic example: https://en.wikipedia.org/wiki/Seven_Bridges_of_K%C3%B6nigsberg
      # related RDF formalisms and guidelines:
      # https://www.w3.org/submissions/CBD/ https://patterns.dataincubator.org/book/graph-per-source.html

      # 👉 graph through indirection of nested hierarchical containers mirroring the local storage structure
      container = fsNames[0..-2].inject(base) do |parent, name| # walk from base to containing node
        c = RDF::URI('#container_' + Digest::SHA2.hexdigest(parent.to_s + name)) # container URI
        graph << RDF::Statement.new(parent, RDF::URI(Contains), c) # parent 👉 child container
        graph << RDF::Statement.new(c, RDF::URI(Title), name)      # container name
        c                                                          # parent container for next iteration
      end

      graph << RDF::Statement.new(container, RDF::URI(Contains), self) # container 👉 graph
    end
  end
  module MIME
    # (MIME, data) -> RDF::Repository
    def readRDF format, content
      graph = RDF::Repository.new.extend Webize::Cache # repository with our behaviours TODO revisit subclass vs extend. IIRC we had weird bugs where third-party code didn't think our subclass was usable as a Repo due to strict equivalence or suchlike

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

          # instantiate reader, bind it to a var, read data -> RDF
          r = reader.new(content, base_uri: self){|_| graph << _ }

          # while here: emit graph pointers after in-doc declarations have updated the graph URI
          # and before said URIs in 'out of band' Reader or Repository properties go out of scope
          [r.base_uri, *graph.each_graph.map(&:name)].map do |_|
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
