%w(read write template).map{|s|
  require_relative "HTML/#{s}.rb"}

# we're having issues with the RDFa parser or serializer being selected and doing something at 99.9% CPU usage until running out of memory and getting the entire server killed by the kernel, so for now,

# disable RDFa handling

# somehow magical conneg dance on writer side is selecting it on ctrl-shift-t or back button, even if the server is no longer running, as if it invisibly preloaded it (but with disabled preloading in browser settings? so maybe we need more <meta> tags or HTTP headers to stop even more preload/preconect/prefect?). on the reader side, it returns a page full of RDFa extraction, which in most cases means nothing, or a reader error, since few people use it except maybe some SEO experts doing what danbri managed to carrot&stick them into doing, or maybe certain Drupal instances did by default without awareness of the site author.

# if you want to try to fixing the undesired RDFa reader/writer selection, maybe fiddle with the q values again? 0.999 vs 1.0, null vs empty vs integer vs string values etc). to try to fix the infinte looping i donno. i still have to write tests and figure out how to debug my own libraries then i will look into thirt party stuff after i get all that squared away

RDF::RDFa::Format.content_type.map{|type|
  RDF::Format.content_types[type] -= [RDF::RDFa::Format]}
