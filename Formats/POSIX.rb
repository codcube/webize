module Webize
  module POSIX ; end

  class POSIX::Node < Resource

    def dir_triples graph
      return Node(join basename + '/').dir_triples graph unless dirURI?
      graph << RDF::Statement.new(self, RDF::URI(Date), node.stat.mtime.iso8601)
      graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename
      (nodes = node.children).map{|child|
        c = Node join child.basename.to_s.gsub(' ','%20').gsub('#','%23')
        if nodes.size > 32
          char = c.basename[0].downcase
          bin = Node join char + '*'
          graph << RDF::Statement.new(self, RDF::URI(Contains), bin)
          graph << RDF::Statement.new(bin, RDF::URI(Contains), c)
          graph << RDF::Statement.new(bin, RDF::URI(Title), char)
        else
          graph << RDF::Statement.new(self, RDF::URI(Contains), c)
        end}
      graph
    end

    def file_triples graph
      graph << RDF::Statement.new(env[:base], RDF::URI('#graphSource'), self) unless self == env[:base] # provenance for non-canonical file source
      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI('http://www.w3.org/ns/posix/stat#File'))
      graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename
      stat = File.stat fsPath
      graph << RDF::Statement.new(self, RDF::URI('http://www.w3.org/ns/posix/stat#size'), stat.size)
      graph << RDF::Statement.new(self, RDF::URI(Date), stat.mtime.iso8601)
      graph << RDF::Statement.new(self, RDF::URI('#pigs'), RDF::URI('#dongs'))
      graph
    end

  end
end
