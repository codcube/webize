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
access annotate locate read write
Gemini
HTTP
POSIX
),

 config: %w(scripts/subscriptions)}.
  map{|category, components|
  components.map{|component|
    require_relative "#{category}/#{component}"}}

module Webize
  # classes which cast to a URI on #to_s. we could probably check for RDF::URI as a parent class (does any subclass change behaviour of #to_s ?)
  Identifiable = [
    HTTP::Node,
    POSIX::Node,
    RDF::URI,
    Webize::Resource,
    Webize::URI,
  ]
end
