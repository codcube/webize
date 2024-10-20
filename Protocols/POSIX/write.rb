module Webize
  class POSIX::Node

    # make containing directory for node, sweeping any blocking files
    def mkdir
      cursor = dirname               # start cursor at dirname

      until cursor == '.'            # until cursor at PWD:
        if File.file?(cursor) ||     # blocking file/symlink?
           File.symlink?(cursor)
          FileUtils.rm cursor        # unlink name
          puts '🧹 ' + cursor        # log sweep operation
        end
        cursor = File.dirname cursor # move cursor up a level
      end

      FileUtils.mkdir_p dirname      # make directory
    end

    # write file, creating containing directory if needed
    def write o
      mkdir unless File.directory? dirname

      File.open(fsPath, 'w') do |f|
        f << o
      end

      self
    end

  end
end
