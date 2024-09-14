module Webize
  class POSIX::Node

    # URI -> boolean
    def directory? = node.directory?
    def exist? = node.exist?
    def file? = node.file?
    def symlink? = node.symlink?

    def mtime = node.mtime

    def size = node.size

  end
end
