module Webize
  class Resource

    def graph_pointer graph
      # 👉 graph so it is reachable/visible in recursive walk, index lookup, treeization, etc algorithms

      # the classic example: https://en.wikipedia.org/wiki/Seven_Bridges_of_K%C3%B6nigsberg
      # related RDF formalisms and guidelines:
      # https://www.w3.org/submissions/CBD/ https://patterns.dataincubator.org/book/graph-per-source.html

      # create hierarchical containers from path structure
      names = fsNames
      names.pop unless dirURI?                         # container node
      nodes.pop if nodes[-1] == 'www'                  # drop 'www' prefix
      container = names.inject(base) do |parent, name| # walk from base to container
        c = RDF::URI('#container_' + Digest::SHA2.hexdigest(parent.to_s + name)) # container URI
        graph << RDF::Statement.new(parent, RDF::URI(Contains), c) # parent 👉 child container
        graph << RDF::Statement.new(c, RDF::URI(Title), name) # container name
        c                                                     # parent container for next iteration
      end

      graph << RDF::Statement.new(container, RDF::URI(Contains), self) # container 👉 graph
    end
  end
end
