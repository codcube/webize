module Webize
  class POSIX::Node

    # URI -> [URI,URI..]

    def find(q) = from_names pathFind q
    def glob = from_names pathGlob
    def grep = from_names pathGrep


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

    # URI -> [path,path..]

    def pathFind(q) = (IO.popen(['find', fsPath, '-iname', q]).read.lines.map &:chomp rescue [])

    def pathGlob = Pathname.glob fsPath

    def pathGrep files = nil
      files = [fsPath] if !files || files.empty?
      q = env[:qs]['q'].to_s
      return [] if q.empty?
      IO.popen(['grep', '-ril', q, *files]).read.lines.map &:chomp rescue []
    end

  end
end