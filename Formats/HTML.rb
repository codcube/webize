%w(read write template).map{|s|
  require_relative "HTML/#{s}.rb"}

# it's still picking the stock HTML/RDFa parsers/serializers sometimes - on ctrl-shift-t or back button, even if the server is no longer running, as if it invisibly preloaded it (but with disabled preloading in browser settings, i think?). this may reduce the frequency of whatever exactly is going on, and maybe cause new errors if something expected the mapping exist (lots of triplrs call other ones internally, say when a ld+json snippet is encountered in HTML etc, plus we added a bunch more of these sorts of things for full recursive embedding). we'll find out if this causes issues. of course you'll want to remove it if you want to use RDFa. note we're not anti-RDFa, it's just that people adopted JsonLD since Google told them to do so for SEO, i think. maybe they did for RDFa also but i guess it's being handled well enough by the generic HTML node webization that i havent noticed any really weird mappings or anything annoying enough that it would be less total annoyance and warrant turning RDFa format back on thus re-enabling whatever is causing it to spin deep inside the Tilt template engine while processing HAML or who the heck knoews what

RDF::RDFa::Format.content_type.map{|type|
  RDF::Format.content_types[type] -= [RDF::RDFa::Format]}
