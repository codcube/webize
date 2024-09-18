%w(read write template).map{|s|
  require_relative "HTML/#{s}.rb"}
