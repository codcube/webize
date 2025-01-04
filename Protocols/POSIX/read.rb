module Webize
  class Resource

    def read = storage.read

  end
  class POSIX::Node

    # indexing preference:
    # in HTTP::Node everything is indexed after a network read, unless no transcoding or merging is occurring ("static asset" fetches)
    # in POSIX::Node we only index if explicity listed. query args are passed to readers so you can do quite a bit of ad-hoc querying without a pre-indexing pass

    # so far listings are for one of these reasons:
    # - a read speedup via cached Turtle (the PDF-extraction util we're using is suspiciously slow - for now only the first read will be an excruciating wait)
    # - data needs to be stored at alternate locations. e.g. an email's data needs to findable at a Message-ID derived location

    IndexedFormats = %w(
application/pdf
message/rfc822)

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

      graph << RDF::Statement.new(env[:base], RDF::URI(Contains), self)          # 👉 directory
      graph << RDF::Statement.new(self, RDF::URI(Date), node.stat.mtime.iso8601) # directory timestamp
      graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename   # directory name
      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI('http://www.w3.org/ns/posix/stat#Directory'))

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
        graph << RDF::Statement.new(self, RDF::URI(Contains), bin)
        graph << RDF::Statement.new(bin, RDF::URI(Title), bin_label) if bin_label
        graph << RDF::Statement.new(bin, contains, c) # bin entry
      }

      graph
    end

    def readFile
      format = fileMIME

      if IndexedFormats.member? format
        puts :index
      else
        graph = readRDF format, readBlob # stored data -> RDF graph
      end

      # storage metadata
      stat = File.stat fsPath
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

  end
end
