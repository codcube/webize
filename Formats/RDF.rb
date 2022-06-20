# coding: utf-8
class WebResource

  # file -> (in-memory) Repository
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
            RDF::RDFa::Reader.new(File.open(fsPath).read, base_uri: env[:base]){|_|
              _.each_statement{|s|
                if Webize::MetaMap.has_key? s.predicate.to_s
                  puts "#{s.predicate} -> #{Webize::MetaMap[s.predicate.to_s]}"
                  s.predicate = RDF::URI Webize::MetaMap[s.predicate.to_s]
                end
                graph << s
              }
            } #rescue puts :RDFa_error
          end
        else
          puts "⚠️ no RDF reader for #{fsPath}" , options if Verbose  # reader undefined for type
        end
      end
    elsif node.directory?                                            # directory RDF
      (dirURI? ? self : join((basename||'')+'/').R(env)).dir_triples graph
    end
    self
  end

  # Repository -> 🐢 file(s)
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

  # Repository -> JSON (s -> p -> o) input datastructure for non-RDF renderers
  def treeFromGraph graph=nil; graph ||= env[:repository]; return {} unless graph
    tree = {}; bnodes = [] # initialize tree and bnode list
    graph.each_triple{|subj,pred,o| # visit triples
      s = subj.to_s; p = pred.to_s  # stringify keys
      tree[s] ||= subj.class==RDF::Node ? {} : {'uri' => s}    # subject
      tree[s][p] ||= []                                        # predicate
      tree[s][p].push o.class==RDF::Node ? (bnodes.push o.to_s # blank-node
                                            tree[o.to_s] ||= {}) : o unless tree[s][p].member? o} # object
    bnodes.map{|n|tree.delete n} # sweep bnodes from subject index
    tree                         # output tree
  end

  module HTTP

    def graphResponse defaultFormat = 'text/html'
      if !env.has_key?(:repository) || env[:repository].empty? # no graph-data found
        return notfound
      end

      status = env[:origin_status] || 200             # response status
      format = selectFormat defaultFormat             # response format
      format += '; charset=utf-8' if %w{text/html text/turtle}.member? format
      head = {'Access-Control-Allow-Origin' => origin,# response header
              'Content-Type' => format,
              'Last-Modified' => Time.now.httpdate,
              'Link' => linkHeader}
      return [status, head, nil] if head?             # header-only response

      body = case format                              # response body
             when /html/
               htmlDocument treeFromGraph             # serialize HTML
             when /atom|rss|xml/
               feedDocument treeFromGraph             # serialize Atom/RSS
             else                                     # serialize RDF
               if writer = RDF::Writer.for(content_type: format)
                 env[:repository].dump writer.to_sym, base_uri: self
               else
                 puts "⚠️  RDF::Writer undefined for #{format}" ; ''
               end
             end

      head['Content-Length'] = body.bytesize.to_s     # response size
      [status, head, [body]]                          # response
    end
  end
end

RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl] # add 🐢 suffix for Turtle

module Webize

  MetaMap = {}
  VocabPath = %w(metadata URI)

  # read metadata map from configuration files
  Dir.children([ConfigPath, VocabPath].join '/').map{|vocab|                # find vocab
    if vocabulary = vocab == 'rdf' ? {uri: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'} : RDF.vocab_map[vocab.to_sym]
      Dir.children([ConfigPath, VocabPath, vocab].join '/').map{|predicate| # find predicate
        destURI = [vocabulary[:uri], predicate].join
        configList([VocabPath, vocab, predicate].join '/').map{|srcURI|     # find mapping
          MetaMap[srcURI] = destURI}}                                       # map predicate
    else
      puts "❓ undefined prefix #{vocab} referenced by vocab map"
    end}

  configList('blocklist/predicate').map{|p|MetaMap[p] = :drop}              # load predicate blocklist

end
