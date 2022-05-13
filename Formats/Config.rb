class WebResource

  def self.configHash file
    Hash[*File.open([__dir__, '../config', file].join '/').readlines.map(&:chomp).map(&:split).flatten]
  end

end
