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

class Array
  def rest = self[1..-1]
end

# 🐢 extension for text/turtle
RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl]

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
