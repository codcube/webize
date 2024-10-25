module Webize
  class Resource

    def read = storage.read

  end
  class POSIX::Node

    def read
      if file?
        readFile
      elsif directory?
        readDir
      else
        puts "no file or directory at #{uri}"
        RDF::Repository.new
      end
    end

    def readDir graph = RDF::Repository.new

      # enforce trailing slash on directory URI
      return Node(join basename + '/').readDir graph unless dirURI?

      graph << RDF::Statement.new(env[:base], RDF::URI('#local_source'), self)         # source provenance
      graph << RDF::Statement.new(self, RDF::URI(Date), node.stat.mtime.iso8601) # directory timestamp
      graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename   # directory name

      (nodes = node.children).map{|child|                   # child nodes
        name = child.basename.to_s                          # node name
        next if name[0] == '.'                              # invisible node

        isDir = child.directory?                            # node type
        name += '/' if isDir

        contains = RDF::URI(isDir ? '#childDir' : '#entry') # containment property
        c = Node join name.gsub(' ','%20').gsub('#','%23')  # child node

        graph << RDF::Statement.new(c, RDF::URI(Title), name)

        char = c.basename[0].downcase
        if nodes.size > 192 # alphanumeric bin
          bin = Node join char + '*'
          bin_label = char
        elsif nodes.size > 32 # alphas or numerics bin
          glob = char.match?(/[0-9]/) ? '[0-9]*' : '[a-zA-Z]*'
          bin = Node join glob
          bin_label = glob[1..3]
        else
          bin = self
        end
        graph << RDF::Statement.new(self, RDF::URI(Contains), bin) unless bin == self
        graph << RDF::Statement.new(bin, RDF::URI(Title), bin_label) if bin_label
        graph << RDF::Statement.new(bin, contains, c) # directory entry
      }

      graph
    end

    def readFile
      graph = readRDF fileMIME, readBlob # read and parse stored data

      # storage metadata
      stat = File.stat fsPath
      graph << RDF::Statement.new(env[:base], RDF::URI('#local_source'), self) # source provenance
      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI('http://www.w3.org/ns/posix/stat#File'))
      graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename
      graph << RDF::Statement.new(self, RDF::URI('http://www.w3.org/ns/posix/stat#size'), stat.size)
      graph << RDF::Statement.new(self, RDF::URI(Date), stat.mtime.iso8601)

      # graph metadata
      graph.each_graph{|g| # graph-source triples
        named_graph = g.name || self # graph URI
        graph << RDF::Statement.new(env[:base], RDF::URI('#local_source'), named_graph) # source
        graph << RDF::Statement.new(env[:base], RDF::URI(Contains), named_graph)  # base -> source
      }

      graph
    end

    def readBlob
      (File.open POSIX::Node(self).fsPath).
        read
    end

  end
end
