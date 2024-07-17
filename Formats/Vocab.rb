class Webize

  MetaMap = {} # vocab URI mapping table

  VocabPath = %w(metadata URI) # path segments to vocab-map config base

  Dir.children([ConfigPath, VocabPath].join '/').map{|vocab|                # for each vocab-map config file:
                                                                            # find vocab prefix defined by RDF library:
    if vocabulary = vocab == 'rdf' ? {uri: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'} : RDF.vocab_map[vocab.to_sym] # special-case RDF symbol so we don't shadow 
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
