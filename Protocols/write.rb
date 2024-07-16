module Webize
  module Graph::Cache

    # Repository -> 🐢 file(s)
    def persist env, dataset # environment, dataset URI

      # query patterns
      timestamp = RDF::Query::Pattern.new :s, RDF::URI(Date), :o  # timestamp
      creator = RDF::Query::Pattern.new :s, RDF::URI(Creator), :o # sender
      to = RDF::Query::Pattern.new :s, RDF::URI(To), :o           # receiver
      type = RDF::Query::Pattern.new :s, RDF::URI(Type), :o       # type

      out = env.has_key?(:updates_only) ? RDF::Repository.new : self # update graph

      each_graph.map{|graph|                              # visit graph
        if g = graph.name
          g = POSIX::Node g                               # graph URI
          f = [g.document, :🐢].join '.'                  # 🐢 location
          log = []

          if File.exist? f  # TODO store version at same URI instead of require new URI for new version?
            # immutable graphs and graph-version-URI minting have so proven to be enough for us
          else # store graph:
            RDF::Writer.for(:turtle).open(f, base_uri: g, prefixes: Prefixes){|f|
              f << graph} # save 🐢
            if env.has_key? :updates_only                       # updates graph:
              out << RDF::Statement.new(dataset, RDF::URI(Contains), g) # 👉 graph
              out << graph                                      # init updates graph
            else                                                # original graph:
              env[:updates] ||= out << RDF::Statement.new(RDF::URI('#updates'), RDF::URI(Type), RDF::URI(Container)) # init updates container
              graph.subjects.map{|subject|                      # 👉 updates
                if dest = graph.query(RDF::Query::Pattern.new subject, RDF::URI(To), :o).first_object
                  env[:dests] ||= {}
                  env[:dests][dest] ||= (
                    dest_bin = RDF::Node.new
                    out << RDF::Statement.new(dest_bin, RDF::URI(Type), RDF::URI(Container))
                    out << RDF::Statement.new(dest_bin, RDF::URI(Title), dest.class == RDF::Literal ? dest : Webize::URI(dest).display_name)
                    out << RDF::Statement.new(RDF::URI('#updates'), RDF::URI(Contains), dest_bin)
                    dest_bin)
                  out << RDF::Statement.new(env[:dests][dest], RDF::URI(Contains), subject)
                else
                  out << RDF::Statement.new(RDF::URI('#updates'), RDF::URI(Contains), subject)
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
                                                          o.respond_to?(:R) ? Webize::URI(o).send(slugify) : o.to_s.split(/[\W_]/)}}]. # tokenize
                                                       flatten.compact.map(&:downcase).uniq - BasicSlugs)]. # apply slug skiplist
                                                     compact.join('.')[0..125].sub(/\.$/,'')+'.🐢'].compact.join '/' # 🕒 path
            unless File.exist? 🕒
              FileUtils.mkdir_p File.dirname 🕒            # create timeline container(s)
              FileUtils.ln f, 🕒 rescue FileUtils.cp f, 🕒 # hardlink 🐢 to 🕒, fallback to copy
              log.unshift [:🕒, ts]
            end
          end
          Console.logger.info log.join ' ' unless log.empty?
        else
          # if for some formats, converting non-RDF to RDF is slow, we could cache turtle by minting a graph URI if nil/empty/default above
          # as it is, we have original file at canonical location so we don't store duplicate graph-data in a 🐢
          #puts "default graph #{env[:base]} #{graph.size} triples"
        end}

      # graph stats
      count = out.size
      out << RDF::Statement.new(dataset, RDF::URI(Size), count) unless count == 0                                # dataset size (triples)
      env[:datasets] ||= (out << RDF::Statement.new(RDF::URI('#datasets'), RDF::URI(Type), RDF::URI(Container))) # dataset container
      out << RDF::Statement.new(RDF::URI('#datasets'), RDF::URI(Contains), dataset)                              # dataset
      if newest = query(timestamp).objects.sort[-1]                                                              # dataset timestamp
        out << RDF::Statement.new(dataset, RDF::URI(Date), newest)
      end

      out # output graph
    end

  end
  module HTML

    def self.cachestamp html, baseURI              # input doc, base-URI
      doc = Nokogiri::HTML.parse html              # parse doc
      if head = doc.css('head')[0]                 # has head?
        base = head.css('base[href]')[0]           # find base node
        return html if base                        # nothing to do
      else                                         # headless?
        Console.logger.warn "⚠️ !head #{baseURI}"  # warn
        head = Nokogiri::XML::Node.new 'head', doc # create head
        if body = doc.css('body')[0]
          body.before head                         # attach head
        else
          doc.add_child head
        end
      end
      base = Nokogiri::XML::Node.new 'base', doc   # create base node
      base['href'] = baseURI                       # set base-URI
      head.add_child base                          # attach base node
      doc.to_html                                  # output doc
    end

  end
end
