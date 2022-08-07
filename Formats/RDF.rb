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
        if reader ||= RDF::Reader.for(**options)                     # find reader
          reader.new(File.open(fsPath).read, base_uri: self){|_|graph << _}     # read RDF
          if options[:content_type]=='text/html' && reader != RDF::RDFa::Reader # read RDFa
            RDF::RDFa::Reader.new(File.open(fsPath).read, base_uri: env[:base]){|g|
              g.each_statement{|statement|
                if predicate = Webize::MetaMap[statement.predicate.to_s]
                  next if predicate == :drop
                  statement.predicate = predicate.R
                end
                graph << statement }} rescue (logger.warn "⚠️ RDFa::Reader failed")
          end
        else
          logger.warn ["⚠️ no RDF reader for #{fsPath}" , options].join # reader not found
        end
      end
    elsif node.directory?                                            # directory RDF
      (dirURI? ? self : join((basename||'')+'/').R(env)).dir_triples graph
    end
    self
  end

  # file -> 🐢 file containing abstract/summary of RDF data
  def preview
    hash = Digest::SHA2.hexdigest uri
    file = [:cache,:overview,hash[0..1],hash[2..-1]+'.🐢'].join '/'  # summary path
    summary = file.R env                                             # summary resource
    return summary if File.exist?(file) && File.mtime(file) >= mtime # cached summary up to date

    fullGraph = RDF::Repository.new                                  # full graph
    miniGraph = RDF::Repository.new                                  # summary graph

    loadRDF graph: fullGraph                                         # load graph
    saveRDF fullGraph if basename.index('msg.') == 0                 # cache RDF extracted from nonRDF
    treeFromGraph(fullGraph).map{|subject, resource|                 # resources to summarize
      subject = subject.R                                            # subject resource
      full = (resource[Type]||[]).find{|t| NoSummary.member? t}      # resource-types retaining full content
      predicates = [Abstract, Audio, Creator, Date, Image, LDP+'contains', DC+'identifier', Title, To, Type, Video, Schema+'itemListElement']
      predicates.push Content if full                                # main content sometimes included in preview
      predicates.push Link unless subject.host                       # include untyped links in local content
      predicates.map{|predicate|                                     # summary-statement predicate
        if o = resource[predicate]
          (o.class == Array ? o : [o]).map{|o|                       # summary-statement object(s)
            if o.class == Hash                                       # blanknode object
              object = RDF::Node.new
              o.map{|p,objets|
                objets.map{|objet|
                  miniGraph << RDF::Statement.new(object, p.R, objet)}} # bnode triples
            else
              object = o
            end
            miniGraph << RDF::Statement.new(subject,predicate.R,object)} # summary-statement triple
        end} if [Image,Abstract,Title,Link,Video].find{|p|resource.has_key? p} || full} # if summary-data exists

    summary.writeFile miniGraph.dump(:turtle,base_uri: self,standard_prefixes: true) # cache summary
    summary                                                          # return summary
  end

  # Repository -> 🐢 file(s)
  def saveRDF repository = nil
    return self unless repository || env[:repository]                # repository to store

    timestamp = RDF::Query::Pattern.new :s, Date.R, :o               # timestamp query-pattern
    creator = RDF::Query::Pattern.new :s, Creator.R, :o              # sender query-pattern
    to = RDF::Query::Pattern.new :s, To.R, :o                        # receiver query-pattern
    type = RDF::Query::Pattern.new :s, Type.R, :o                    # RDF type query-pattern

    (repository || env[:repository]).each_graph.map{|graph|          # graph
      graphURI = (graph.name || self).R                              # graph URI
      this = graphURI == self
      f = graphURI.fsPath
      f += 'index' if f[-1] == '/'
      f += '.🐢'                                                     # storage location
      log = []

      unless File.exist? f
        POSIX.container f                                            # container(s)
        RDF::Writer.for(:turtle).open(f){|f|f << graph}              # store 🐢
        log << ["\e[38;5;48m#{graph.size}⋮🐢\e[1m",[graphURI.display_host, graphURI.path, "\e[0m"].join] unless this
      end

      # if graph location is not on timeline, link to timeline. TODO other index locations
      if !graphURI.to_s.match?(HourDir) && (ts = graph.query(timestamp).first_value) && ts.match?(/^\d\d\d\d-/)

        t = ts.split /\D/                                            # slice to unit segments
        🕒 = [t[0..3], t.size < 4 ? '0' : nil,                       # timeslice containers
              [t[4..-1],                                             # remaining timeslices in basename
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
          log.unshift [:🕒, ts] unless this                          # log timestamp
        end
      end
      logger.info log.join ' ' unless log.empty?}
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
                 logger.warn "⚠️  RDF::Writer undefined for #{format}" ; ''
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
    if vocabulary = vocab == 'rdf' ? {uri: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'} : RDF.vocab_map[vocab.to_sym] # enable our use of RDF symbol as vocab prefix
      Dir.children([ConfigPath, VocabPath, vocab].join '/').map{|predicate| # find predicate
        destURI = [vocabulary[:uri], predicate].join
        configList([VocabPath, vocab, predicate].join '/').map{|srcURI|     # find mapping
          MetaMap[srcURI] = destURI}}                                       # map predicate
    else
      Console.logger.warn "❓ undefined prefix #{vocab} referenced by vocab map"
    end}

  configList('blocklist/predicate').map{|p|MetaMap[p] = :drop}              # load predicate blocklist

end
