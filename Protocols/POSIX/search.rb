module Webize
  class POSIX::Node

    # URI -> [URI,URI..]

    def find(q) = fromNames pathFind q
    def glob = fromNames pathGlob
    def grep = fromNames pathGrep


    # find filesystem nodes and map to URI space
    # (URI, env) -> [URI, URI, ..]
    def nodes
      q = env[:qs]                                # query arguments
      if directory?
        if q['f'] && !q['f'].empty?               # FIND exact
          find q['f']

        elsif q['find'] && !q['find'].empty?      # FIND substring matches
          find '*' + q['find'] + '*'

        elsif q['q'] && !q['q'].empty?            # GREP
          grep

        else                                      # LS (dir)
          [self, # dir + static index nodes
           *Node(join [dirURI? ? nil : [basename, '/'],
                       '{index,readme,README}*'].join).glob]
        end
      elsif file?                                 # LS (file)
        [self]
      elsif fsPath.match? GlobChars               # GLOB
        if q['q'] && !q['q'].empty?               # GREP in GLOB
          if (g = pathGlob).empty?
            []
          else
            fromNames pathGrep g[0..999]
          end
        else                                      # parametric GLOB
          glob
        end
      else                                        # default set
        fromNames Pathname.glob fsPath + '.*'
      end
    end

    # URI -> [path,path..]

    def pathFind(q) = IO.popen(['find', fsPath, '-iname', q]).read.lines.map &:chomp

    def pathGlob = Pathname.glob fsPath

    def pathGrep files = nil
      return [] if (q = env[:qs]['q'].to_s).empty? # query arg is required

      files = if !files || files.empty?            # default search space is current container
                [fsPath]
              else
                files
              end.map &:to_s

      IO.popen(['grep', '-ril', '--exclude-dir=.*', q, *files]).read.lines.map &:chomp
    end

  end
end
