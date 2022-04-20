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

    # URI -> pathname. a one way map, though path-hierarchy is often preserved
    def fsPath
      @fsPath ||= if !host                                ## local
                    if parts[0] == 'msg'                   # Message-ID -> sharded containers
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
                     else                                  # query hash for file-sibling or dir-child
                       (query ? join(dirURI? ? query_hash : [basename, query_hash].join('.')).R : self).parts.map{|part|
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

    # HTTP-level pointers for basic directory navigation
    def dirMeta
      env[:links][:up] = if !path || path == '/'                   # up to parent of subdomain
                           '//' + host.split('.')[1..-1].join('.')
                         else                                      # up to parent container
                           [File.dirname(env['REQUEST_PATH']), '/', (env['QUERY_STRING'] && !env['QUERY_STRING'].empty?) ? ['?',env['QUERY_STRING']] : nil].join
                         end
      env[:links][:down] = '*' if (!host || offline?) && dirURI?   # down to child-nodes
    end

    def fileAttr key
      val = nil
      Async.task do |task|
              task.async {
                result = `attr -qg #{key} #{shellPath} 2> /dev/null` # read file attribute
                val = result if $?.success? }
      end
      val
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

    # pathnames -> URIs
    def fromNodes ps
      base = host ? self : '/'.R
      pathbase = host ? host.size : 0
      ps.map{|p|
        base.join(p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')).R env}
    end

    # URI -> Pathname
    def node; Pathname.new fsPath end

    # URI -> [pathname]
    def nodeFind q; `find #{Shellwords.escape fsPath} -iname #{Shellwords.escape q}`.lines.map &:chomp end
    def nodeGlob; Pathname.glob fsPath end
    def nodeGrep files = nil
      files = [fsPath] if !files || files.empty?
      q = env[:qs]['q'].to_s
      return [] if q.empty?
      args = q.shellsplit rescue q.split(/\W/)
      file_arg = files.map{|file| Shellwords.escape file.to_s }.join ' '
      case args.size
      when 0
        return []
      when 2 # two unordered terms
        cmd = "grep -rilZ #{Shellwords.escape args[0]} #{file_arg} | xargs -0 grep -il #{Shellwords.escape args[1]}"
      when 3 # three unordered terms
        cmd = "grep -rilZ #{Shellwords.escape args[0]} #{file_arg} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -il #{Shellwords.escape args[2]}"
      when 4 # four unordered terms
        cmd = "grep -rilZ #{Shellwords.escape args[0]} #{file_arg} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -ilZ #{Shellwords.escape args[2]} | xargs -0 grep -il #{Shellwords.escape args[3]}"
      else   # N ordered term
        cmd = "grep -ril -- #{Shellwords.escape args.join '.*'} #{file_arg}"
      end
      `#{cmd} | head -n 1024`.lines.map &:chomp
    end

  end
  include POSIX
end
