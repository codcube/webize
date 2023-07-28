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

  module Graph
  end

  module Graph::Sort

    def group attr, env

    end

  end

  module Graph::Cache

    # Repository -> 🐢 file(s)
    def persist env, dataset # environment, dataset URI

      # query patterns
      timestamp = RDF::Query::Pattern.new :s, Date.R, :o  # timestamp
      creator = RDF::Query::Pattern.new :s, Creator.R, :o # sender
      to = RDF::Query::Pattern.new :s, To.R, :o           # receiver
      type = RDF::Query::Pattern.new :s, Type.R, :o       # type

      out = env.has_key?(:updates_only) ? RDF::Repository.new : self # update graph

      each_graph.map{|graph|                              # visit graph
        graph.extend Graph::Sort
        if g = graph.name
          g = POSIX::Node g                               # graph URI
          f = [g.document, :🐢].join '.'                  # 🐢 location
          log = []

          if File.exist? f  # TODO store version instead of require new URI for new state. immutable graphs paired with smart graph-URI minting have so far proven to be (mostly) enough. new versions are also already stored at new timeline location.
            
          else # store graph:
            RDF::Writer.for(:turtle).open(f){|f|f << graph} # save 🐢
            if env.has_key? :updates_only                       # updates graph:
              out << RDF::Statement.new(dataset, Contains.R, g) # 👉 graph
              out << graph                                      # init updates graph
            else                                                # original graph:
              env[:updates] ||= out << RDF::Statement.new('#updates'.R, Type.R, Container.R) # init updates container
              graph.subjects.map{|subject|                      # 👉 updates
                if dest = graph.query(RDF::Query::Pattern.new subject, To.R, :o).first_object
                  env[:dests] ||= {}
                  env[:dests][dest] ||= (
                    dest_bin = RDF::Node.new
                    out << RDF::Statement.new(dest_bin, Type.R, Container.R)
                    out << RDF::Statement.new(dest_bin, Title.R, dest.class == RDF::Literal ? dest : Webize::URI(dest).display_name)
                    out << RDF::Statement.new('#updates'.R, Contains.R, dest_bin)
                    dest_bin)
                  out << RDF::Statement.new(env[:dests][dest], Contains.R, subject)
                else
                  out << RDF::Statement.new('#updates'.R, Contains.R, subject)
                end
              }
            end

            log << ["\e[38;5;48m#{graph.size}⋮🐢\e[1m", [g.display_host, g.path, "\e[0m"].join]
          end

          # link to timeline if not already there and we have a timestamp
          if !g.to_s.match?(/^\/\d\d\d\d\/\d\d\/\d\d\/\d\d/) && (ts = graph.query(timestamp).first_value) && ts.match?(/^\d\d\d\d-/)
            t = ts.split /\D/                                 # split timestamp
            🕒 = [t[0..3], t.size < 4 ? '0' : nil, [t[4..-1], # timeline containers
                                                    ([g.slugs, [type, creator, to].map{|pattern|          # name tokens from graph and query pattern
                                                        slugify = pattern==type ? :display_name : :slugs  # slug verbosity
                                                        graph.query(pattern).objects.map{|o|              # query for slug-containing triples
                                                          o.respond_to?(:R) ? o.R.send(slugify) : o.to_s.split(/[\W_]/)}}]. # tokenize
                                                       flatten.compact.map(&:downcase).uniq - BasicSlugs)]. # apply slug skiplist
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
      env[:datasets] ||= (
        out << RDF::Statement.new('#datasets'.R, Type.R, Container.R)     # dataset container
        out << RDF::Statement.new('#datasets'.R, Type.R, Directory.R))
      out << RDF::Statement.new('#datasets'.R, Contains.R, dataset)       # dataset
      if newest = query(timestamp).objects.sort[-1]                       # dataset timestamp
        out << RDF::Statement.new(dataset, Date.R, newest)
      end

      out # output graph
    end
  end
end
