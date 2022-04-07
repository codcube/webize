{Formats: %w(URI Archive Audio Calendar Code CSS CSV Feed Form Gemini HTML Image JSON Mail Markdown Message MIME Org PDF POSIX RDF Subtitle Text Video),
 Protocols: %w(POSIX Gemini HTTP),
 config: %w(icons meta site)}.
  map{|category, components|
  components.map{|component|
    require_relative "#{category}/#{component}"}}

Verbose = ENV.has_key? 'VERBOSE'
