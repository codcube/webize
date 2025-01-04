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

    # Node -> RDF
    def readFile
      format = fileMIME             # MIME type
      locator = fsPath              # graph locator
      if IndexedFormats.member? format
        🐢 = locator + '.🐢'        # cache locator
        if File.exist? 🐢           # cache exists?
          puts "cache hit for #{locator}"
          readRDF 'text/turtle', File.open(🐢).read
        else                        # cache and index graph
          puts "➕ #{locator}"      # log index-add
          graph = (readRDF format,  # read graph
                           File.open(locator).read).index env, self
          RDF::Writer.for(:turtle). # cache graph in 🐢
            open(🐢, base_uri: self, prefixes: Prefixes){|cache| cache << graph}
          graph
        end
      else
        readRDF format, File.open(locator).read
      end
    end
  end
  class Resource

    def read = storage.read # cast to POSIX::Node and read

  end
end

# # source metadata
# stat = File.stat locator
# graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI('http://www.w3.org/ns/posix/stat#File'))
# graph << RDF::Statement.new(self, RDF::URI(Title), basename) if basename
# graph << RDF::Statement.new(self, RDF::URI('http://www.w3.org/ns/posix/stat#size'), stat.size)
# graph << RDF::Statement.new(self, RDF::URI(Date), stat.mtime.iso8601)
