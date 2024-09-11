module Webize
  module POSIX ; end

  class POSIX::Node < Resource

    def dir_triples graph

      # enforce trailing slash on directory URI
      return Node(join basename + '/').dir_triples graph unless dirURI?

      graph << RDF::Statement.new(env[:base], RDF::URI(Contains), self) unless self == env[:base] # provenance for non-canonical directory source
      graph << RDF::Statement.new(self, RDF::URI(Date), node.stat.mtime.iso8601) # directory timestamp
      graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename   # directory name

      (nodes = node.children).map{|child|                              # child nodes
        name = child.basename.to_s                                     # node name
        next if name[0] == '.'                                         # invisible child

        contains = RDF::URI(child.directory? ? '#childDir' : '#entry') # containment property
        c = Node join name.gsub(' ','%20').gsub('#','%23')             # child node

        graph << RDF::Statement.new(c, RDF::URI(Title), name)

        if nodes.size > 32 # alpha binning of large directories - TODO generic alpha binning in graph-summarizer
          char = c.basename[0].downcase
          bin = Node join char + '*'
          graph << RDF::Statement.new(self, RDF::URI(Contains), bin)
          graph << RDF::Statement.new(bin, RDF::URI(Title), char)
          graph << RDF::Statement.new(bin, contains, c)  # directory entry in alpha-bin
        else
          graph << RDF::Statement.new(self, contains, c) # directory entry
        end}
      graph
    end

    def file_triples graph
      # provenance and naming
      graph << RDF::Statement.new(env[:base], RDF::URI('#source'), self) unless env[:base] == self # source-graph reference

      #graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI('http://www.w3.org/ns/posix/stat#File'))
      graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename

      # fs metadata
      stat = File.stat fsPath
      graph << RDF::Statement.new(self, RDF::URI('http://www.w3.org/ns/posix/stat#size'), stat.size)
      graph << RDF::Statement.new(self, RDF::URI(Date), stat.mtime.iso8601)
      graph
    end

  end
end
