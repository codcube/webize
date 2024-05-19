module Webize
  module POSIX ; end

  class POSIX::Node < Resource

    def dir_triples graph
      return Node(join basename + '/').dir_triples graph unless dirURI?
      graph << RDF::Statement.new(self, RDF::URI(Date), node.stat.mtime.iso8601)
      (nodes = node.children).map{|child|
        c = Node join child.basename.to_s.gsub(' ','%20').gsub('#','%23')
        if nodes.size > 32
          bin = Node join c.basename[0].downcase + '*'
          graph << RDF::Statement.new(self, RDF::URI(Contains), bin)
          graph << RDF::Statement.new(bin, RDF::URI(Contains), c)
        else
          graph << RDF::Statement.new(self, RDF::URI(Contains), c)
        end}
      graph
    end

    def file_triples graph
      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI('http://www.w3.org/ns/posix/stat#File'))
      stat = File.stat fsPath
      graph << RDF::Statement.new(self, RDF::URI('http://www.w3.org/ns/posix/stat#size'), stat.size)
      graph << RDF::Statement.new(self, RDF::URI(Date), stat.mtime.iso8601)
      graph
    end

  end
end
