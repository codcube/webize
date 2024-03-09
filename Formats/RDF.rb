# coding: utf-8
RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl] # add 🐢 suffix for turtle files

module Webize
  MetaMap = {}
  VocabPath = %w(metadata URI)

  # load metadata map
  Dir.children([ConfigPath, VocabPath].join '/').map{|vocab|                # find vocab
    if vocabulary = vocab == 'rdf' ? {uri: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'} : RDF.vocab_map[vocab.to_sym] # vocabulary prefix
      Dir.children([ConfigPath, VocabPath, vocab].join '/').map{|predicate| # find predicates
        destURI = [vocabulary[:uri], predicate].join                        # expand predicate URI
        configList([VocabPath, vocab, predicate].join '/').map{|srcURI|     # parse mapping entries
          MetaMap[srcURI] = destURI}}                                       # map predicate
    else
      Console.logger.warn "❓ undefined prefix #{vocab} referenced by vocab map"
    end}

  configList('blocklist/predicate').map{|p|MetaMap[p] = :drop}              # load predicate blocklist

  module Graph
  end

end
