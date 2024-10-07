module Webize
  class POSIX::Node

    # document path,
    # also document as a verb due to side effect of container creation
    def document
      mkdir
      fsPath
    end

    # follow symlinks to find real filename extension. IO-dependent cousin to pure name-based #extname in URI.rb
    # we use this in few enough places that maybe we should inline it at calling sites to not introduce confusion
    def extension = File.extname realpath

    # [pathname, ..] -> [URI, ..]
    def fromNames ps
      base = host ? self : RDF::URI('/')
      pathbase = host ? host.size : 0
      ps.map{|p|
        Node base.join p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')}
    end

    # URI -> Pathname
    def node = Pathname.new fsPath

    def realpath
      File.realpath fsPath
    end

  end
  class Resource

    def preview = Webize::Resource [storage.document, :preview, :🐢].join('.'), env

  end
end
