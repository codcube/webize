require 'linkeddata'

{Formats: %w(
Config
URI
HTML.read Bookmarks
HTML.write
HTML.templates
MIME
POSIX
RDF
Archive
Audio
Code
CSS
CSV
Date
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
read
write
Gemini
HTTP
POSIX
),
 config: %w(scripts/subscriptions)}.
  map{|category, components|
  components.map{|component|
    require_relative "#{category}/#{component}"}}

class Array
  def rest = self[1..-1]
end
