require 'linkeddata'

{Formats: %w(
Config
URI
HTML
MIME
Archive
Audio
Bookmarks
Code
CSS
CSV
Date
Feed
Form
Gemini
Image
InstantMessage
JSON
Mail
Markdown
Org
PDF
Subtitle
Text
Video
Vocab
XML),

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

# our one monkey-patch
class Array
  def rest = self[1..-1]
end
