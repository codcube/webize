{Formats: %w(
Config
URI
HTML.read HTML.massage HTML.write
MIME
POSIX
RDF
Archive
Audio
Calendar
Code
CSS
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
access
location
Gemini
HTTP
POSIX
),
 config: %w(scripts/site)}.
  map{|category, components|
  components.map{|component|
    require_relative "#{category}/#{component}"}}
