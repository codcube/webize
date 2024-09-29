module Webize
  class POSIX::Node

    def dirname = node.dirname

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

    def extension = File.extname realpath

    # [pathname, ..] -> [URI, ..]
    def fromNames ps
      base = host ? self : RDF::URI('/')
      pathbase = host ? host.size : 0
      ps.map{|p|
        Node base.join p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')}
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
           (query ? Node(join dirURI? ? query_digest : [basename, query_digest, extname].join('.')) : self).parts.map{|part|
             Rack::Utils.unescape_path part}   # path map
         end,
         (dirURI? && !query) ? '' : nil].      # preserve trailing slash on directory name
          flatten.compact
      end.join('/')
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
