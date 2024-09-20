%w(read write template).map{|s|
  require_relative "HTML/#{s}.rb"}

# it's still picking the stock HTML/RDFa parsers/serializers sometimes. this may reduce the frequency, or cause other errors if something expects it to exist. we'll find out
RDF::Format.content_types['text/html'] -= [RDF::RDFa::Format]
