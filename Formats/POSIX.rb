module Webize
  module POSIX ; end

  class POSIX::Node < Resource

    def dir_triples graph
      return Node(join basename + '/').dir_triples graph unless dirURI?
      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Container))
      graph << RDF::Statement.new(self, RDF::URI(Date), node.stat.mtime.iso8601)
      children = node.children
      graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename

      # 👉 contained nodes
      children.select{|n|n.basename.to_s[0] != '.'}.map{|child|
        base = child.basename.to_s
        c = Node join base.gsub(' ','%20').gsub('#','%23')
        if child.directory?
          c += '/'
          graph << RDF::Statement.new(c, RDF::URI(Type), RDF::URI(Container))
          graph << RDF::Statement.new(c, RDF::URI(Title), base + '/')
        elsif child.file?
          graph << RDF::Statement.new(c, RDF::URI(Title), base)
          graph << RDF::Statement.new(c, RDF::URI(Type), MIME.format_icon(c.fileMIME))
        end
        if children.size > 48
          alphas = {}
          alpha = base[0].downcase
          alpha = '0' unless ('a'..'z').member? alpha
          a = RDF::URI('#' + alpha)
          alphas[alpha] ||= (
            graph << RDF::Statement.new(a, RDF::URI(Type), RDF::URI(Container))
            graph << RDF::Statement.new(self, RDF::URI(Contains), a))
          graph << RDF::Statement.new(a, RDF::URI(Contains), c)
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
