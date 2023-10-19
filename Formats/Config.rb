require 'console'
require 'pathname'

module Webize
  include Console

  Console.logger.verbose! false

  ConfigPath = [__dir__, '../config'].join '/'
  ConfigRelPath = Pathname(ConfigPath).relative_path_from Dir.pwd

  # path -> String
  def self.configData path
    File.open([ConfigPath, path].join '/').read.chomp
  end

  # path -> Hash
  def self.configHash path
    Hash[*configTokens(path)]
  end

  # path -> Array
  def self.configList path
    configData(path).lines.map &:chomp
  end

  # path -> Regexp
  def self.configRegex path
    Regexp.new configData(path), Regexp::IGNORECASE
  end

  # path -> Array
  def self.configTokens path
    configData(path).split
  end

end
