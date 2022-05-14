module Webize

  ConfigPath = [__dir__, '../config'].join '/'

  # path -> String
  def self.configData path
    File.open([ConfigPath, path].join '/').read.chomp
  end

  # path -> Hash
  def self.configHash path
    Hash[*configList(path).map(&:split).flatten]
  end

  # path -> Array
  def self.configList path
    configData(path).lines.map &:chomp
  end
end
