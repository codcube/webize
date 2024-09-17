module Webize
  module Cache

    # Repository -> 🐢(s)
     def persist env, summarize: false
                                                          # query pattern for:
      timestamp = RDF::Query::Pattern.new :s, RDF::URI(Date), :o  # timestamp
      creator = RDF::Query::Pattern.new :s, RDF::URI(Creator), :o # sender
      to = RDF::Query::Pattern.new :s, RDF::URI(To), :o           # receiver
      type = RDF::Query::Pattern.new :s, RDF::URI(Type), :o       # type

      each_graph.map{|graph|           # for each
        next unless g = graph.name     # named graph:
        g = POSIX::Node g              # graph URI
        f = [g.document, :🐢].join '.' # 🐢 location

        if File.exist? f          # cache hit (mint a new graph URI to store a new version)
          # TODO automagic graph-version-URI minting and RDF indexing (with append-only URI lists)
          graph << RDF::Statement.new(env[:base], RDF::URI('#archive'), g)# link to archived content
          next
        end

        RDF::Writer.for(:turtle).open(f, base_uri: g, prefixes: Prefixes){|f|f << graph} # cache 🐢

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

        graph << RDF::Statement.new(env[:base], RDF::URI(summarize ? '#entry' : Contains), g)# link to updated content
        graph << RDF::Statement.new(g, RDF::URI('#new'), true)# mark as updated
        Console.logger.info log.join ' '                      # log message
      }
      self
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
