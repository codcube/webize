module Webize

  ConfigPath = [__dir__, '../config'].join '/'

  def self.configData path
    File.open([ConfigPath, path].join '/').read
  end

  def self.configHash path
    Hash[*configData(path).lines.map(&:chomp).map(&:split).flatten]
  end

end
