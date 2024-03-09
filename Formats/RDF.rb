# coding: utf-8

# add 🐢 suffix map for turtle format
RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl]

module Webize

  MetaMap = {} # {String -> URI} metadata mapping table

  VocabPath = %w(metadata URI) # path to vocab mapping files

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
    # namespace for util methods for RDF Graph/Repository instances
  end

end
