module Webize
  module Cache

    # Repository -> 🐢(s)
     def persist env, summarize: false
                                                          # query pattern for:
      timestamp = RDF::Query::Pattern.new :s, RDF::URI(Date), :o  # timestamp
      creator = RDF::Query::Pattern.new :s, RDF::URI(Creator), :o # sender
      to = RDF::Query::Pattern.new :s, RDF::URI(To), :o           # receiver
      type = RDF::Query::Pattern.new :s, RDF::URI(Type), :o       # type
      summaries = RDF::Repository.new if summarize

      each_graph.map{|graph|           # for each
        next unless g = graph.name     # named graph:
        g = POSIX::Node g              # graph URI
        docBase = g.document           # document path
        f = [docBase, :🐢].join '.' # 🐢 location

        if File.exist? f          # cache hit (mint a new graph URI to store a new version)
          # TODO automagic graph-version-URI minting and RDF indexing (with append-only URI lists)
          graph << RDF::Statement.new(env[:base], RDF::URI('#archive'), g)# link to archived content
          next
        end

        RDF::Writer.for(:turtle).                      # graph -> 🐢
          open(f, base_uri: g, prefixes: Prefixes){|f|
          f << graph}

        log = ["\e[38;5;48m#{graph.size}⋮🐢\e[1m", [g.display_host, g.path, "\e[0m"].join] # canonical location

        if !g.to_s.match?(/^\/\d\d\d\d\/\d\d\/\d\d\/\d\d/) && # if graph not already located on timeline,
           (ts = graph.query(timestamp).first_value) &&       # and we have a timestamp value in RDF,
           ts.match?(/^\d\d\d\d-/)                            # in iso8601-compatible format
          t = ts.split /\D/                                   # split timestamp

          🕒 = [t[0..3], t.size < 4 ? '0' : nil,              # nested timeslice (year -> month -> day -> hour) containers
                [t[4..-1],                                    # timeofday basename prefix
                 ([g.slugs, [type, creator, to].map{|pattern| # for name tokens in graph query patterns:
                     graph.query(pattern).objects.map{|o|     # query for slug providers
                       if Identifiable.member? o.class        # URI?
                         Webize::URI(o).display_name          # slug from URI
                       else
                         o.to_s.split /[\W_]/                 # slugs from literal
                       end}}].flatten.compact.map(&:downcase).# normalize slugs
                    uniq - BasicSlugs)].                      # apply slug skiplist
                  compact.join('.')[0..125].                  # join basename (max-length 128)
                  sub(/\.$/,'') + '.🐢'].                     # append turtle extension
                 compact.join '/'                             # join path

          unless File.exist? 🕒
            FileUtils.mkdir_p File.dirname 🕒                 # create timeline container(s)
            FileUtils.ln f, 🕒 rescue FileUtils.cp f, 🕒      # hard link 🐢 to 🕒, w/ copy fallback operation
            log.unshift [:🕒, ts]                             # timeline location
          end
        end

        Console.logger.info log.join ' '                      # log message

        if summarize                # summarize?
          summary = RDF::Graph.new  # summary
          graph.each_statement{|s|  # walk graph
            next unless [Creator, Date, Image, Link, To, Title, Type, Video].member? s.predicate.to_s
            summary << s}           # summary << statement

          RDF::Writer.for(:turtle). # summary >> 🐢
            open(g.preview.uri, base_uri: g, prefixes: Prefixes){|f|
            f << summary}

          host = RDF::URI('//' + (g.host || 'localhost'))                      # host container
          summary << RDF::Statement.new(env[:base], RDF::URI(Contains), host)  # base 👉 host container
          summary << RDF::Statement.new(host, RDF::URI(Title), g.display_host) # host label
          summary << RDF::Statement.new(host, RDF::URI('#graph'), g)           # host container 👉 summarized graph
          summaries << summary                                                 # summary graph of graphs
        else
          graph << RDF::Statement.new(env[:base], RDF::URI(Contains), g) # base 👉 full graph
          graph << RDF::Statement.new(g, RDF::URI('#new'), true)         # tag as new/updated
        end
      }

      summarize ? summaries : self
    end

  end
end
