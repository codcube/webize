module Webize
  class POSIX::Node

    # make containing directory for node
    def mkdir = FileUtils.mkdir_p dirname

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
