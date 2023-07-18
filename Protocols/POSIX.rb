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
  end

  class POSIX::Resource < URI
    include MIME

    def dir_triples graph
      graph << RDF::Statement.new(self, Type.R, Container.R)
      graph << RDF::Statement.new(self, Date.R, node.stat.mtime.iso8601)
      children = node.children
      alpha_binning = children.size > 52
      graph << RDF::Statement.new(self, Type.R, Directory.R) unless alpha_binning
      graph << RDF::Statement.new(self, Title.R, basename)
      children.select{|n|n.basename.to_s[0] != '.'}.map{|child| # 👉 contained nodes
        base = child.basename.to_s
        c = join base.gsub(' ','%20').gsub('#','%23')
        if child.directory?
          c += '/'
          graph << RDF::Statement.new(c, Type.R, Container.R)
          graph << RDF::Statement.new(c, Title.R, base + '/')
        else
          graph << RDF::Statement.new(c, Title.R, base)
          graph << RDF::Statement.new(c, Type.R, MIME.format_icon(c.R.fileMIME))
        end
        if alpha_binning
          alphas = {}
          alpha = base[0].downcase
          alpha = '0' unless ('a'..'z').member? alpha
          a = ('#' + alpha).R
          alphas[alpha] ||= (
            graph << RDF::Statement.new(a, Type.R, Container.R)
            graph << RDF::Statement.new(a, Type.R, Directory.R)
            graph << RDF::Statement.new(self, Contains.R, a))
          graph << RDF::Statement.new(a, Contains.R, c)
        else
          graph << RDF::Statement.new(self, Contains.R, c)
        end}
      graph
    end

    def file_triples graph
      graph << RDF::Statement.new(self, Type.R, 'http://www.w3.org/ns/posix/stat#File'.R)
      stat = File.stat fsPath
      graph << RDF::Statement.new(self, 'http://www.w3.org/ns/posix/stat#size'.R, stat.size)
      graph << RDF::Statement.new(self, Date.R, stat.mtime.iso8601)
      graph
    end

    def read
      File.open(fsPath).read
    end

    # create containing dir(s) and return locator for document
    def document
      mkdir
      documentPath
    end

    # find filesystem nodes and map to URI space
    # (URI, env) -> [URI, URI, ..]
    def fsNodes
      q = env[:qs]                                # query params
      if directory?
        if q['f'] && !q['f'].empty?               # FIND exact
          find q['f']
        elsif q['find'] && !q['find'].empty?      # FIND substring matches
          find '*' + q['find'] + '*'
        elsif q['q'] && !q['q'].empty?            # GREP
          grep
        elsif !host && path == '/'
          (Pathname.glob Webize::ConfigRelPath.join('bookmarks/{home.u,search.🐢}')).map{|n| n.to_s.R env }
        elsif !dirURI?                            # LS dir
          [self]                                  # minimal (no trailing-slash)
        else                                      # detailed (trailing-slash)
          [self,
           *join('{index,readme,README}*').R(env).glob] # directory index
        end
      elsif file?                                 # LS file
        [self]
      elsif fsPath.match? GlobChars               # GLOB
        if q['q'] && !q['q'].empty?               # GREP inside GLOB
          if (g = nodeGlob).empty?
            []
          else
            fromNodes nodeGrep g[0..999]
          end
        else                                      # parametric GLOB
          glob
        end
      else                                        # default set
        fromNodes Pathname.glob fsPath + '.*'
      end
    end

    # URI -> pathname
    def fsPath
      @fsPath ||= if !host                                ## local URI
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
                     else                                  # query hash to basename for sibling file or directory child
                       (query ? join(dirURI? ? query_hash : [basename, query_hash, extname].join('.')).R : self).parts.map{|part|
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

    def shellPath
      Shellwords.escape fsPath
    end

    def writeFile o
      FileUtils.mkdir_p node.dirname
      File.open(fsPath,'w'){|f| f << o }
      self
    end

    # URI -> boolean
    def directory?; node.directory? end
    def exist?; node.exist? end
    def file?; node.file? end
    def symlink?; node.symlink? end

    # URI -> [URI,URI..]
    def find q; fromNodes nodeFind q end
    def glob; fromNodes nodeGlob end
    def grep; fromNodes nodeGrep end

    # URI -> ETag
    def fileETag
      Digest::SHA2.hexdigest [uri, mtime, node.size].join
    end

    # [path, path..] -> [URI, URI..]
    def fromNodes ps
      base = host ? self : '/'.R
      pathbase = host ? host.size : 0
      ps.map{|p|
        base.join(p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')).R env}
    end

    def mtime; node.mtime end

    # URI -> Pathname
    def node; Pathname.new fsPath end

    # URI -> [path,path..]
    def nodeFind q; IO.popen(['find', fsPath, '-iname', q]).read.lines.map &:chomp rescue [] end
    def nodeGlob; Pathname.glob fsPath end
    def nodeGrep files = nil
      files = [fsPath] if !files || files.empty?
      q = env[:qs]['q'].to_s
      return [] if q.empty?
      IO.popen(['grep', '-ril', q, *files]).read.lines.map &:chomp rescue []
    end

  end
end
