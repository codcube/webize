module Webize
  class POSIX::Node

    # make containing dir(s) with pre-cleanup for files in name slots where dirs are going to go
    def mkdir
      dir = cursor = dirURI? ? fsPath.sub(/\/$/,'') : File.dirname(fsPath) # strip slash from cursor (any blocking filename won't have one)
      until cursor == '.'                # cursor at root?
        if File.file? cursor
          FileUtils.rm cursor            # unlink file/link blocking location
          puts '🧹 ' + cursor            # log fs-sweep
        end
        cursor = File.dirname cursor     # up to parent container
      end
      FileUtils.mkdir_p dir              # make container
    end

    def write o
      FileUtils.mkdir_p dirname # make containing dir(s)

      File.open(fsPath,'w'){|f|
        f << o }

      self
    end

  end
end
