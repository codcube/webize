# coding: utf-8
RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl] # add 🐢 suffix for turtle files

module Webize

  MetaMap = {}
  VocabPath = %w(metadata URI)

  # load metadata map
  Dir.children([ConfigPath, VocabPath].join '/').map{|vocab|                # find vocab
    if vocabulary = vocab == 'rdf' ? {uri: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'} : RDF.vocab_map[vocab.to_sym] # vocabulary prefix
      Dir.children([ConfigPath, VocabPath, vocab].join '/').map{|predicate| # find predicates
        destURI = [vocabulary[:uri], predicate].join
        configList([VocabPath, vocab, predicate].join '/').map{|srcURI|     # parse mapping
          MetaMap[srcURI] = destURI}}                                       # map predicate
    else
      Console.logger.warn "❓ undefined prefix #{vocab} referenced by vocab map"
    end}

  configList('blocklist/predicate').map{|p|MetaMap[p] = :drop}              # load predicate blocklist

  module GraphCache

    # Repository -> 🐢 file(s)
    def persist env, dataset # environment, dataset URI

      # query patterns
      timestamp = RDF::Query::Pattern.new :s, Date.R, :o  # timestamp
      creator = RDF::Query::Pattern.new :s, Creator.R, :o # sender
      to = RDF::Query::Pattern.new :s, To.R, :o           # receiver
      type = RDF::Query::Pattern.new :s, Type.R, :o       # type

      out = env.has_key?(:updates_only) ? RDF::Repository.new : self # update graph

      each_graph.map{|graph|                              # visit graph
        if g = graph.name
          g = g.R                                         # graph URI
          f = [g.document, :🐢].join '.'                  # 🐢 location
          log = []

          # TODO backup old versions instead of require new URI for new state - immutable graphs have so far proven to be enough paired with smart graph-URI minting
          unless File.exist? f                              # persist graph:
            RDF::Writer.for(:turtle).open(f){|f|f << graph} # save 🐢

            out << graph if env.has_key? :updates_only      # add to update graph
            graph.subjects.map{|subject|                    # denote resources as updated
              out << RDF::Statement.new('#updates'.R, Contains.R, subject)}

            log << ["\e[38;5;48m#{graph.size}⋮🐢\e[1m", [g.display_host, g.path, "\e[0m"].join]
          end

          # link graph to timeline .. if not already there and we have valid timestamp
          if !g.to_s.match?(/^\/\d\d\d\d\/\d\d\/\d\d\/\d\d/) && (ts = graph.query(timestamp).first_value) && ts.match?(/^\d\d\d\d-/)
            t = ts.split /\D/                                 # split timestamp
            🕒 = [t[0..3], t.size < 4 ? '0' : nil, [t[4..-1], # timeline containers
                                                    ([g.slugs, [type, creator, to].map{|pattern|          # name tokens from graph and query pattern
                                                        slugify = pattern==type ? :display_name : :slugs  # slug verbosity
                                                        graph.query(pattern).objects.map{|o|              # query for slug-containing triples
                                                          o.respond_to?(:R) ? o.R.send(slugify) : o.to_s.split(/[\W_]/)}}]. # tokenize
                                                       flatten.compact.map(&:downcase).uniq - WebResource::URIs::BasicSlugs)].          # apply slug skiplist
                                                     compact.join('.')[0..125].sub(/\.$/,'')+'.🐢'].compact.join '/' # 🕒 path
            unless File.exist? 🕒
              FileUtils.mkdir_p File.dirname 🕒            # create timeline container(s)
              FileUtils.ln f, 🕒 rescue FileUtils.cp f, 🕒 # hardlink 🐢 to 🕒, fallback to copy
              log.unshift [:🕒, ts]
            end
          end
          Console.logger.info log.join ' ' unless log.empty?
        end}

      # graph stats
      count = out.size
      out << RDF::Statement.new(dataset, Size.R, count) unless count == 0 # dataset triple-count
      out << RDF::Statement.new(dataset, Title.R, dataset.path || '/')    # dataset title
      out << RDF::Statement.new('#datasets'.R, Contains.R, dataset)       # dataset listing
      if newest = query(timestamp).objects.sort[-1]                       # dataset timestamp
        out << RDF::Statement.new(dataset, Date.R, newest)
      end

      out # output graph
    end
  end
end
class WebResource

  # [MIME, data] -> Repository (in-memory, unpersisted)
  def readRDF format = fileMIME, content = read
    repository = RDF::Repository.new.extend Webize::GraphCache # TODO why does this work, but not subclassing RDF::Repository (missing methods like #insert_statement)
    case format                                                    # content type:TODO needless reads? stop media reads earlier..
    when /octet.stream/                                            #  blob
    when /^audio/                                                  #  audio
      audio_triples repository
    when /^image/                                                  #  image
      repository << RDF::Statement.new(self, Type.R, Image.R)
      repository << RDF::Statement.new(self, Title.R, basename)
    when /^video/                                                  #  video
      repository << RDF::Statement.new(self, Type.R, Video.R)
      repository << RDF::Statement.new(self, Title.R, basename)
    else
      if reader ||= RDF::Reader.for(content_type: format)          # find reader
        reader.new(content, base_uri: self){|_|repository << _}    # read RDF

        if format == 'text/html' && reader != RDF::RDFa::Reader    # read RDFa
          RDF::RDFa::Reader.new(content, base_uri: self){|g|
            g.each_statement{|statement|
              if predicate = Webize::MetaMap[statement.predicate.to_s]
                next if predicate == :drop
                statement.predicate = predicate.R
              end
              repository << statement
            }} rescue (logger.debug "⚠️ RDFa::Reader failed on #{uri}")
        end
      else
        logger.warn ["⚠️ no RDF reader for " , format].join # reader not found
      end
    end
    repository
  end
end

