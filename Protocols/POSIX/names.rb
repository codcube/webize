module Webize
  class POSIX::Node

    # URI name methods. filesystem syscall/io allowed here unlike the 'pure functions' of URI.rb

    # (IO) document path (noun) and verb due to side effect of container creation
    def document
      mkdir
      fsPath
    end

    # (IO) follow symlinks to real file and return its extension
    def extension = File.extname realpath

    # (pure) map filesystem paths to URIs
    # [path, ...] -> [URI, ...]
    def fromNames ps
      base = host ? self : RDF::URI('/')
      pathbase = host ? host.size : 0
      ps.map{|p|
        Node base.join p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')}
    end

    # (pure) URI -> Pathname
    def node = Pathname.new fsPath

    # (IO) follow symlinks to real file
    def realpath
      File.realpath fsPath
    end

  end
  class Resource

    def preview = Webize::Resource [storage.document, :preview, :🐢].join('.'), env

  end
end
