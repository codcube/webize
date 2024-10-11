module Webize
  class POSIX::Node

    # URI name methods. filesystem syscall/io allowed here, unlike the pure functions im URI.rb

    # (IO) document path (noun) and container initialization (verb)
    def document
      mkdir
      fsPath
    end

    # (IO) follow symlinks and return name-extension
    def extension = File.extname realpath

    # (pure) [pathname] -> [URI]
    def fromNames ps
      base = host ? self : RDF::URI('/')
      pathbase = host ? host.size : 0
      ps.map{|p|
        Node base.join p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')}
    end

    # (pure) URI -> pathname
    def node = Pathname.new fsPath

    # (IO) follow symlinks to real location
    def realpath
      File.realpath fsPath
    end

  end
  class Resource

    def preview = Webize::Resource [storage.document, :preview, :🐢].join('.'), env

  end
end
