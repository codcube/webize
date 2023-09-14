{Formats: %w(
Config
URI
HTML.read HTML.write
MIME
POSIX
RDF
Archive
Audio
Calendar
Code
CSV
Feed
Form
Gemini
Image
JSON
Mail
Markdown
Message
Org
PDF
Subtitle
Text
Video),
 Protocols: %w(
POSIX
Gemini
HTTP),
 config: %w(scripts/site)}.
  map{|category, components|
  components.map{|component|
    require_relative "#{category}/#{component}"}}
