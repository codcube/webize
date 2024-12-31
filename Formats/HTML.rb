%w(read write template).map{|s|
  require_relative "HTML/#{s}.rb"}

# we're having issues with the RDFa parsers/serializers doing something at 99.9% CPU usage until running out of memory and getting the entire server killed by the kernel, so shut them of for now,

# details: somehow RDFa::Writer is selected for rendering visible on ctrl-shift-t or back-button, even if server is no longer running, as if it invisibly preloaded (but with disabled preloading in browser settings? so maybe we need more <meta> tags or HTTP headers to stop more preload/preconnect/prefetch calls). on the reader side, it returns a page full of RDFa extraction, which in most cases means nothing, or a reader error, since few people use it except maybe some SEO experts doing what danbri managed to carrot&stick them into doing, or maybe certain Drupal instances did by default without awareness of the site author.

# if you want to try to fixing the reader/writer selection, maybe fiddle with the q values again? 0.999 vs 1.0, nil vs empty-string vs integer vs number-in-string etc). to try to fix the infinite looping, i donno. i still have to write tests and figure out how to debug my own libraries then i will look into thirt party stuff after that. maybe there's some loop detection missing but last time i ctrl-c'd it i thiunk it was actually something about canonicalizing QNames or something maybe triggering schema/ontology/context-file fetching over the net? i think it or JSON-LD might do that but i don't sue either one so not sure tbh. last time in fact i noticed it hanging here it was trying to get something at PURL.org which was hosted by Archive.org that was down due to a hack.. fun times

RDF::RDFa::Format.content_type.map{|type|
  RDF::Format.content_types[type] -= [RDF::RDFa::Format]}
 
