# coding: utf-8
%w(fileutils pathname shellwords).map{|d| require d }
class WebResource

  def dir_triples graph
    graph << RDF::Statement.new(self, Type.R, 'http://www.w3.org/ns/ldp#Container'.R)
    graph << RDF::Statement.new(self, Title.R, basename)
    graph << RDF::Statement.new(self, Date.R, node.stat.mtime.iso8601)
    nodes = node.children.select{|n|n.basename.to_s[0] != '.'} # find contained nodes
    nodes.map{|child|                                          # 👉 contained nodes
      graph << RDF::Statement.new(self, 'http://www.w3.org/ns/ldp#contains'.R, (join child.basename.to_s.gsub(' ','%20').gsub('#','%23')))}
  end

  module URIs

    # document location for resource
    def docPath
      file = fsPath                          # resource path

      if file[-1] == '/'                     # directory locator - no fs stat needed
        file += 'index'
      elsif directory?                       # directory at location
        file += '/index'
      end

      POSIX.container file                   # create container(s)
      file                                   # document path
    end

    # find filesystem nodes and map to URI space
    # (URI, env) -> [URI, URI, ..]
    def fsNodes
      q = env[:qs]                                        # query
      nodes = if directory?
                if q['f'] && !q['f'].empty?               # FIND exact
                  summarize = true
                  find q['f']
                elsif q['find'] && !q['find'].empty?      # FIND substring
                  summarize = true
                  find '*' + q['find'] + '*'
                elsif q['q'] && !q['q'].empty?            # GREP
                  grep
                elsif !host && path == '/'
                  (Pathname.glob Webize::ConfigRelPath.join('bookmarks/{home.u,search.html}')).map{|_| _.R env}
                else                                      # LS dir
                  pat = if dirURI?                        # has trailing-slash?
                          summarize = true                # summary of
                          '*'                             #  all files
                        else                              # minimal directory info
                          env[:links][:down] = [basename, '/'].join
                          [env[:links][:down], '{index,readme,README}*'].join
                        end
                  [self, *join(pat).R(env).glob]
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
              else                                        # default document-set
                fromNodes Pathname.glob fsPath + '.*'
              end
      nodes.map! &:preview if summarize                   # summarize nodes
      #logger.debug [:nodes, nodes].join ' '
      nodes                                               # nodes
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
                     ((!path || dirURI?) && !query) ? '' : nil]. # trailing slash on directory URI
                      flatten.compact
                  end.join('/')
    end
  end

  def shellPath
    Shellwords.escape fsPath
  end

  def writeFile o
    FileUtils.mkdir_p node.dirname
    File.open(fsPath,'w'){|f| f << o }
    self
  end
  module HTTP

    def fileResponse
      if env[:client_etags].include?(etag = fileETag)     # cached at client
        return [304, {}, []]
      end

      Rack::Files.new('.').serving(Rack::Request.new(env), fsPath).yield_self{|s,h,b|
        case s                                            # status
        when 200
          s = env[:origin_status] if env[:origin_status]  # upstream status
        when 304
          return [304, {}, []]                            # cached at client
        end
        format = fileMIME                                 # file format
        h['Content-Type'] = format
        h['Content-Type'] = 'application/javascript; charset=utf-8' if h['Content-Type']=='application/javascript'
        h['ETag'] = etag
        h['Expires'] = (Time.now + 3e7).httpdate if format.match? FixedFormat
        h['Last-Modified'] ||= mtime.httpdate
        [s, h, b]}
    end
  end

  module POSIX

    # create containing dir for path
    def self.container path
      dir = File.dirname path # container path

      until path == '.'       # unlink files and symlinks blocking container path
        FileUtils.rm path if File.file?(path) || File.symlink?(path)
        path = File.dirname path
      end

      FileUtils.mkdir_p dir   # create container(s)
    end

    # HTTP-level pointers for directory navigation
    def dirMeta
      root = !path || path == '/'
      if host && root                                            # up to parent domain
        env[:links][:up] = '//' + host.split('.')[1..-1].join('.')
      elsif !root                                                # up to parent path
        env[:links][:up] = [File.dirname(env['REQUEST_PATH']), '/', (env['QUERY_STRING'] && !env['QUERY_STRING'].empty?) ? ['?',env['QUERY_STRING']] : nil].join
      end
      env[:links][:down] = '*' if (!host || offline?) && dirURI? # down to children
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

    # [path,path..] -> [URI,URI..]
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
  include POSIX
end
