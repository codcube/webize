require 'console'
require 'pathname'

module Webize

  ConfigPath = [__dir__, '../config'].join '/'
  ConfigRelPath = Pathname(ConfigPath).relative_path_from Dir.pwd

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

  def self.configRegex path
    Regexp.new configData(path), Regexp::IGNORECASE
  end

end
