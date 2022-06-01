# coding: utf-8
%w(fileutils pathname shellwords).map{|d| require d }
class WebResource

  def dir_triples graph
    graph << RDF::Statement.new(self, Type.R, (LDP + 'Container').R)
    graph << RDF::Statement.new(self, Title.R, basename)
    graph << RDF::Statement.new(self, Date.R, node.stat.mtime.iso8601)
    nodes = node.children.select{|n|n.basename.to_s[0] != '.'} # find contained nodes
    nodes.map{|child|                                          # 👉 contained nodes
      graph << RDF::Statement.new(self, (LDP+'contains').R, (join child.basename.to_s.gsub(' ','%20').gsub('#','%23')))}
  end

  module URIs

    # find filesystem nodes and map to URI space
    # (URI, env) -> [URI, URI, ..]
    def fsNodes
      q = env[:qs]                                        # query

      nodes = if directory?
                if q['f'] && !q['f'].empty?               # FIND exact
                  summarize = !env[:fullContent]
                  find q['f']
                elsif q['find'] && !q['find'].empty?      # FIND substring
                  summarize = !env[:fullContent]
                  find '*' + q['find'] + '*'
                elsif q['q'] && !q['q'].empty?            # GREP
                  grep
                else                                      # LS dir
                  [self,                                  # inline indexes and READMEs to result set
                   *join((dirURI? ? '' : (basename || '') + '/' ) + '{index,readme,README}*').R(env).glob]
                end
              elsif file?                                 # LS file
                [self]
              elsif fsPath.match? GlobChars               # GLOB
                if q['q'] && !q['q'].empty?               # GREP in GLOB
                  if (g = nodeGlob).empty?
                    []
                  else
                    fromNodes nodeGrep g[0..999]
                  end
                else                                      # arbitrary GLOB
                  summarize = !env[:fullContent]
                  glob
                end
              else                                        # default GLOB
                fromNodes Pathname.glob fsPath + '.*'
              end

      if summarize                                          # 👉 unsummarized
        env[:links][:down] = HTTP.qs q.merge({'fullContent' => nil})
        nodes.map! &:preview
      end

      if env[:fullContent] && q.respond_to?(:except)        # 👉 summarized
        env[:links][:up] = HTTP.qs q.except('fullContent')
      end

      nodes
    end

    # URI -> pathname. a one way map, though path-hierarchy is often preserved
    def fsPath
      @fsPath ||= if !host                                ## local
                    if parts.empty?
                      %w(.)
                    elsif parts[0] == 'msg'                # Message-ID -> sharded containers
                      id = Digest::SHA2.hexdigest Rack::Utils.unescape_path parts[1]
                      ['mail', id[0..1], id[2..-1]]
                    else                                   # path map
                      parts.map{|part| Rack::Utils.unescape_path part}
                    end
                  else                                    ## remote
                    [host.split('.').reverse,              # domain-name containers
                     if (path && path.size > 496) || parts.find{|p|p.size > 127}
                       hash = Digest::SHA2.hexdigest uri   # huge name, hash and shard
                       [hash[0..1], hash[2..-1]]
                     else                                  # query hash to basename for sibling file or directory child
                       (query ? join(dirURI? ? query_hash : [basename, query_hash, extname].join('.')).R : self).parts.map{|part|
                         Rack::Utils.unescape_path part}   # path map
                     end,
                     ((!path || dirURI?) && !query) ? '' : nil]. # trailing slash on directoryURI
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

  module POSIX

    # initialize containing dir
    def self.container path
      dir = File.dirname path
      until path == '.' # garbage collect files or dangling symlinks in the way
        FileUtils.rm path if File.file?(path) || File.symlink?(path)
        path = File.dirname path # up a level
      end
      FileUtils.mkdir_p dir # create containing dir
    end

    # HTTP-header pointers for basic directory navigation
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

    # URI -> URIs
    def find q; fromNodes nodeFind q end
    def glob; fromNodes nodeGlob end
    def grep; fromNodes nodeGrep end

    # [path,..] -> [URI,..]
    def fromNodes ps
      base = host ? self : '/'.R
      pathbase = host ? host.size : 0
      ps.map{|p|
        base.join(p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')).R env}
    end

    # URI -> Pathname
    def node; Pathname.new fsPath end

    # URI -> [path]
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
