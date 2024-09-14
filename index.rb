require 'linkeddata'

{Formats: %w(
Config
URI
HTML.read
HTML.write
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
JSON
Mail
Markdown
Message
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

class Array
  def rest = self[1..-1]
end

module Webize

  # classes which become a URI on #to_s
  Identifiable = [
    HTTP::Node,
    POSIX::Node,
    RDF::URI,
    Webize::Resource,
    Webize::URI,
  ]

end
