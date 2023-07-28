# coding: utf-8
%w(fileutils pathname shellwords).map{|d| require d }
module Webize

  # addresses valid for all network protocols
  LocalAddrs = Socket.ip_address_list.map &:ip_address # local addresses
  PeerHosts = Hash[*File.open([ENV['PREFIX'],'/etc/hosts'].join).readlines.map(&:chomp).map{|l|
                     addr, *names = l.split
                     names.map{|host|
                       [host, addr]}}.flatten]         # peer host -> peer addr map
  PeerAddrs = PeerHosts.invert                         # peer addr -> peer host map

  module POSIX
    def self.Node uri, env=nil
      env ? Node.new(uri).env(env) : Node.new(uri)
    end
  end

  class POSIX::Node
    include MIME

    def dirname; node.dirname end

    def extension; File.extname realpath end

    # create containing dir(s) and return locator
    def document
      mkdir
      doc = fsPath
      if doc[-1] == '/' # dir/ -> dir/index
        doc + 'index'
      else              # file -> file
        doc
      end
    end

    def Node uri
      POSIX::Node.new(uri).env env
    end

    # find filesystem nodes and map to URI space
    # (URI, env) -> [URI, URI, ..]
    def nodes
      q = env[:qs]                                # query params
      if directory?
        if q['f'] && !q['f'].empty?               # FIND exact
          find q['f']
        elsif q['find'] && !q['find'].empty?      # FIND substring matches
          find '*' + q['find'] + '*'
        elsif q['q'] && !q['q'].empty?            # GREP
          grep
        elsif !host && path == '/'
          (Pathname.glob Webize::ConfigRelPath.join(HomePage)).map{|n|
            Node n }
        elsif !dirURI?                            # LS dir
          [self]                                  # minimal (no trailing-slash)
        else                                      # detailed (trailing-slash)
          [self,
           *Node(join '{index,readme,README}*').glob] # directory index
        end
      elsif file?                                 # LS file
        [self]
      elsif fsPath.match? GlobChars               # GLOB
        if q['q'] && !q['q'].empty?               # GREP inside GLOB
          if (g = pathGlob).empty?
            []
          else
            from_names pathGrep g[0..999]
          end
        else                                      # parametric GLOB
          glob
        end
      else                                        # default set
        from_names Pathname.glob fsPath + '.*'
      end
    end

    # URI -> pathname
    def fsPath
      if !host                                ## local URI
        if parts.empty?
          %w(.)
        elsif parts[0] == 'msg'                # Message-ID -> sharded containers
          id = Digest::SHA2.hexdigest Rack::Utils.unescape_path parts[1]
          ['mail', id[0..1], id[2..-1]]
        else                                   # path map
          parts.map{|part| Rack::Utils.unescape_path part}
        end
      else                                    ## global URI
        [host.split('.').reverse,              # domain-name containers
         if (path && path.size > 496) || parts.find{|p|p.size > 127}
           hash = Digest::SHA2.hexdigest uri   # huge name, hash and shard
           [hash[0..1], hash[2..-1]]
         else                                  # query hash to basename in sibling file or directory child
           (query ? Node(join dirURI? ? query_hash : [basename, query_hash, extname].join('.')) : self).parts.map{|part|
             Rack::Utils.unescape_path part}   # path map
         end,
         (dirURI? && !query) ? '' : nil].      # preserve trailing slash on directory name
          flatten.compact
      end.join('/')
    end

    # create containing dir(s)
    def mkdir
      dir = cursor = dirURI? ? fsPath.sub(/\/$/,'') : File.dirname(fsPath) # strip slash from cursor (blocking filename doesn't have one)
      until cursor == '.'                # cursor at root?
        if File.file?(cursor) || File.symlink?(cursor)
          FileUtils.rm cursor            # unlink file/link blocking location
          puts '🧹 ' + cursor            # log fs-sweep
        end
        cursor = File.dirname cursor     # up to parent container
      end
      FileUtils.mkdir_p dir              # make container
    end

    def realpath
      File.realpath fsPath
    end

    def write o
      FileUtils.mkdir_p dirname
      File.open(fsPath,'w'){|f| f << o }
      self
    end

    # URI -> boolean
    def directory?; node.directory? end
    def exist?; node.exist? end
    def file?; node.file? end
    def symlink?; node.symlink? end

    # URI -> [URI,URI..]
    def find q; from_names pathFind q end
    def glob; from_names pathGlob end
    def grep; from_names pathGrep end

    # [path, path..] -> [URI, URI..]
    def from_names ps
      base = host ? self : '/'.R
      pathbase = host ? host.size : 0
      ps.map{|p|
        Node base.join p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')}
    end

    def mtime; node.mtime end

    # URI -> Pathname
    def node; Pathname.new fsPath end

    # URI -> [path,path..]
    def pathFind q; IO.popen(['find', fsPath, '-iname', q]).read.lines.map &:chomp rescue [] end
    def pathGlob; Pathname.glob fsPath end
    def pathGrep files = nil
      files = [fsPath] if !files || files.empty?
      q = env[:qs]['q'].to_s
      return [] if q.empty?
      IO.popen(['grep', '-ril', q, *files]).read.lines.map &:chomp rescue []
    end

    def size; node.size end

  end
end
