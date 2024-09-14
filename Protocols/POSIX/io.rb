module Webize
  class POSIX::Node

    def read
      if file?
        readFile
      elsif directory?
        readDir
      end
    end

    def readDir graph = RDF::Repository.new

      # enforce trailing slash on directory URI
      return Node(join basename + '/').readDir graph unless dirURI?

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

    def readFile
      graph = readRDF fileMIME, readBlob # file data

      # file metadata
      stat = File.stat fsPath
      graph << RDF::Statement.new(env[:base], RDF::URI('#source'), self) # source provenance
      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI('http://www.w3.org/ns/posix/stat#File'))
      graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename
      graph << RDF::Statement.new(self, RDF::URI('http://www.w3.org/ns/posix/stat#size'), stat.size)
      graph << RDF::Statement.new(self, RDF::URI(Date), stat.mtime.iso8601)

      graph
    end

    def readBlob
      (File.open POSIX::Node(self).fsPath).
        read
    end

    def write o
      FileUtils.mkdir_p dirname # create containing dirs

      File.open(fsPath,'w'){|f|
        f << o }

      self
    end

  end
end
