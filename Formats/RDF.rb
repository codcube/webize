# coding: utf-8
class WebResource

  # file -> RDF::Repository
  def loadRDF graph: env[:repository] ||= RDF::Repository.new
    options = {}
    if node.file?                                                    # file
      case options[:content_type] = fileMIME                         # content type
      when /octet.stream/                                            # blob
      when /^audio/                                                  # audio file
        audio_triples graph
      when /^image/                                                  # image file
        graph << RDF::Statement.new(self, Type.R, Image.R)
        graph << RDF::Statement.new(self, Title.R, basename)
      when /^video/                                                  # video file
        graph << RDF::Statement.new(self, Type.R, Video.R)
        graph << RDF::Statement.new(self, Title.R, basename)
      else
        if reader ||= RDF::Reader.for(**options)                     # instantiate reader
          reader.new(File.open(fsPath).read, base_uri: self){|_|graph << _} # read
          if options[:content_type]=='text/html' && reader != RDF::RDFa::Reader  # secondary reader (RDFa) on HTML
            RDF::RDFa::Reader.new(File.open(fsPath).read, base_uri: env[:base]){|_|graph << _ } rescue puts :RDFa_error
          end
        else
          puts "⚠️ no RDF reader for #{uri}" , options                # reader undefined for type
        end
      end
    elsif node.directory?                                            # directory RDF
      (dirURI? ? self : join((basename||'')+'/').R(env)).dir_triples graph
    end
    self
  end

  # RDF::Repository -> 🐢 file(s)
  def saveRDF repository = nil
    return self unless repository || env[:repository]                # repository

    timestamp = RDF::Query::Pattern.new :s, Date.R, :o               # timestamp query-pattern
    creator = RDF::Query::Pattern.new :s, Creator.R, :o              # sender query-pattern
    to = RDF::Query::Pattern.new :s, To.R, :o                        # receiver query-pattern
    type = RDF::Query::Pattern.new :s, Type.R, :o                    # RDF type query-pattern

    (repository || env[:repository]).each_graph.map{|graph|          # graph
      graphURI = (graph.name || self).R                              # graph URI
      f = graphURI.fsPath
      f += 'index' if f[-1] == '/'
      f += '.🐢'                                                     # storage location
      log = []
      unless File.exist? f
        POSIX.container f                                            # container(s)
        RDF::Writer.for(:turtle).open(f){|f|f << graph}              # store 🐢
        log << "\e[38;5;48m#{'%2d' % graph.size}⋮🐢 \e[1m#{graphURI.host ? graphURI : ('http://'+env['HTTP_HOST']).R.join(graphURI)}\e[0m" if Verbose || graphURI != self
      end
      # if graph is not on timeline and has a timestamp
      if !graphURI.to_s.match?(HourDir) && (ts = graph.query(timestamp).first_value) && ts.match?(/^\d\d\d\d-/)
        ts = ts.split /\D/                                           # slice time-segments
        🕒 = [ts[0..3], ts.size < 4 ? '0' : nil,                     # timeslice containers
              [ts[4..-1],                                            # remaining timeslices in basename
               ([graphURI.slugs,                                     # graph name slugs
                 [type, creator, to].map{|pattern|                   # query pattern
                   slugify = pattern==type ? :display_name : :slugs  # slugization method
                   graph.query(pattern).objects.map{|o|              # query for slug-containing triples
                  o.respond_to?(:R) ? o.R.send(slugify) : o.to_s.split(/[\W_]/)}}]. # tokenize slugs
                  flatten.compact.map(&:downcase).uniq - BasicSlugs)].          # normalize slugs
                compact.join('.')[0..125].sub(/\.$/,'')+'.🐢'].compact.join '/' # build timeline path
        unless File.exist? 🕒
          FileUtils.mkdir_p File.dirname 🕒                          # create missing timeslice containers
          FileUtils.ln f, 🕒 rescue FileUtils.cp f, 🕒               # link 🐢 to timeline
          log << ['🕒', 🕒] if Verbose
        end
      end
      puts log.join ' ' unless log.empty?}
    self
  end

  # RDF::Repository -> JSON (s->p->o). input data-structure for Atom/HTML/RSS renderers
  def treeFromGraph graph=nil; graph ||= env[:repository]; return {} unless graph
    tree = {}                    # initialize tree
    bnodes = []                  # blank nodes
    graph.each_triple{|subj,pred,o| # triples
      p = pred.to_s                 # predicate
      p = MetaMap[p] if MetaMap.has_key? p
      unless p == :drop
        #puts [pred, p].join " -> " if Verbose && pred != p
        puts [p, o].join "\t" unless p.match? /^https?:/
        s = subj.to_s            # subject
        tree[s] ||= subj.class==RDF::Node ? {} : {'uri' => s} # subject storage
        tree[s][p] ||= []                                     # predicate storage
        tree[s][p].push o.class==RDF::Node ? (bnodes.push o.to_s # bnode object
                                              tree[o.to_s] ||= {}) : o unless tree[s][p].member? o # object
      end}
    bnodes.map{|n|tree.delete n} # sweep bnode-ids from index
    tree                         # output tree
  end

end
