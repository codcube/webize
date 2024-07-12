# coding: utf-8

# add 🐢 suffix map for turtle format
RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl]

module Webize

  MetaMap = {} # {String -> URI} mapping table

  VocabPath = %w(metadata URI) # path segments to vocabulary-map config

  # Ruby classes capable of representing an RDF resource with an identifier
  Identifiable = [RDF::URI,
                  Webize::URI,
                  Webize::Resource,
                  Webize::POSIX::Node,
                 ]

  # load metadata map
  Dir.children([ConfigPath, VocabPath].join '/').map{|vocab|                # for each config file:
                                                                            # vocabulary prefix
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

  module Graph
    # namespace for util methods for RDF Graph/Repository instances
  end

end
