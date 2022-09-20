{Formats: %w(Config URI Archive Audio Calendar Code CSV Feed Form Gemini HTML Image JSON Mail Markdown Message MIME Org PDF RDF Subtitle Text Video),
 Protocols: %w(POSIX Gemini HTTP),
 config: %w(scripts/site)}.
  map{|category, components|
  components.map{|component|
    require_relative "#{category}/#{component}"}}
