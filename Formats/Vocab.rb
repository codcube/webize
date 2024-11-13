module Webize

  RDF.vocab_map[:ui] = {uri: 'https://www.w3.org/ns/ui#', class_name: 'UI'}

  MetaMap = {} # vocab URI mapping table

  VocabPath = %w(metadata URI) # path segments to vocab-map config base

  Dir.children([ConfigPath, VocabPath].join '/').map{|vocab|                # for each vocab-map config file:
    if vocabulary = RDF.vocab_map[vocab.to_sym]                             # lookup vocab prefix
      Dir.children([ConfigPath, VocabPath, vocab].join '/').map{|predicate| # for each predicate:
        destURI = [vocabulary[:uri], predicate].join                        # expand predicate URI
        configList([VocabPath, vocab, predicate].join '/').map{|srcURI|     # parse mapping entries
          MetaMap[srcURI] = destURI}}                                       # map predicate
    else
      Console.logger.warn "❓ undefined prefix #{vocab} referenced by vocab map"
    end}

  configList('blocklist/predicate').map{|p|                                 # load predicate blocklist
    MetaMap[p] = :drop}                                                     # add 'drop' directive to table

end
