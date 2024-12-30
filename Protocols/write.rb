module Webize
  module Cache

    # cache and timeline-index named graphs to 🐢, given repository instance
     def persist env, base
                                                          # query pattern for:
      timestamp = RDF::Query::Pattern.new :s, RDF::URI(Date), :o  # timestamp
      creator = RDF::Query::Pattern.new :s, RDF::URI(Creator), :o # sender
      to = RDF::Query::Pattern.new :s, RDF::URI(To), :o           # receiver
      type = RDF::Query::Pattern.new :s, RDF::URI(Type), :o       # type

      each_graph.map{|graph|           # for each
        next unless g = graph.name     # named graph
        g = POSIX::Node g              # graph URI
        docBase = g.document           # document base-locator
        f = [docBase, :🐢].join '.'    # 🐢 locator
        next if File.exist? f          # persisted - mint new graph URI to store new version TODO do that here?

        RDF::Writer.for(:turtle).      # graph -> 🐢
          open(f, base_uri: g, prefixes: Prefixes){|f|
          f << graph}

        graph << RDF::Statement.new(g, RDF::URI('#new'), true)

        log = ["\e[38;5;48m#{graph.size}⋮🐢\e[1m", [g.display_host, g.path, "\e[0m"].join] # log cache location

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
            FileUtils.mkdir_p File.dirname 🕒                 # make timeline container(s)
            FileUtils.ln f, 🕒 # rescue FileUtils.cp f, 🕒      # link 🐢 to 🕒, with copy as fallback operation
            log.unshift [:🕒, ts]                             # timeline location
          end
        end

        Console.logger.info log.join ' '                      # output log message
      }

      if newest = query(timestamp).objects.sort[-1] # dataset timestamp
        # there's so much noise with "like/play/favorite" causing last-updated bumps so not super useful to find non-updating feeds, but it occasionally achieves the desired results
        self << RDF::Statement.new(base, RDF::URI(Date), newest)
      end

      self      # persisted-to-cached-graphs repository
     end
  end
end
