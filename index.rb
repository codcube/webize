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

module webize
  # classes which cast to URI-string on #to_s. we could instead check for RDF::URI in parent class (does any subclass change behaviour of #to_s ?)
  Identifiable = [
    HTTP::Node,
    POSIX::Node,
    RDF::URI,
    Webize::Resource,
    Webize::URI,
  ]
end
