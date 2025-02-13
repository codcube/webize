module Webize
  class POSIX::Node

    # Node -> Repository
    def read
      if file?
        readFile
      elsif directory?
        readDir
      else
        # something like a "dangling" symlink may send you here
        puts "no file or directory at #{uri}"
        RDF::Repository.new
      end
    end

    def readDir graph = RDF::Repository.new

      # enforce trailing slash on directory URI
      return Node(join [basename, '/'].join).readDir graph unless dirURI?

      # table entry for directory-list graph 
      graph_pointer graph, true                                                  # 👉 directory

      graph << RDF::Statement.new(self, RDF::URI(Date), node.stat.mtime.iso8601) # timestamp

      (nodes = node.children).map{|child|                   # child nodes
        name = child.basename.to_s                          # node name
        next if name[0] == '.'                              # invisible node
        if isDir = child.directory?                         # node type
          name += '/'
        end
        contains = RDF::URI(isDir ? '#childDir' : '#entry') # containment predicate
        c = Node join name.gsub(' ','%20').gsub('#','%23')  # child node
        graph << RDF::Statement.new(c, RDF::URI(Title), name)
        graph << RDF::Statement.new(c, RDF::URI(Type), RDF::URI('http://www.w3.org/ns/posix/stat#Directory')) if isDir
        if nodes.size > 48
          char = c.basename[0].downcase
          bin = Node join char + '*/'
          bin.graph_pointer graph, true                 # 👉 bin
          graph << RDF::Statement.new(bin, contains, c) # bin entry
        else
          graph << RDF::Statement.new(self, contains, c) # entry
        end

      }

      graph
    end

    # Node -> RDF
    def readFile
      format = fileMIME
      if IndexedFormats.member? format
       (readRDF format, File.open(fsPath).read).index env, self
      else
        readRDF format, File.open(fsPath).read
      end
    end
  end
  class Resource
    def read = storage.read # cast to POSIX::Node and read
  end
end
