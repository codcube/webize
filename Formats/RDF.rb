# coding: utf-8
class WebResource

  # file -> Repository
  def loadRDF graph: env[:repository] ||= RDF::Repository.new
    if node.file?                                                    # file
      readRDF fileMIME, File.open(fsPath).read, graph
    elsif node.directory?                                            # directory
      (dirURI? ? self : join((basename || '') + '/').R(env)).dir_triples graph
    end
    self
  end

  NoSummary = [Image,                      # don't summarize these resource types
               Schema + 'ItemList',
               Schema + 'Readme',
               SIOC + 'MicroPost'].map &:R

  # file -> 🐢 file (abstract/summary of data)
  def preview
    hash = Digest::SHA2.hexdigest uri
    file = [:cache,:overview,hash[0..1],hash[2..-1]+'.🐢'].join '/'  # summary path
    summary = file.R env                                             # summary resource
    return summary if File.exist?(file) && File.mtime(file) >= mtime # cached summary up to date
    fullGraph = RDF::Repository.new                                  # full graph
    miniGraph = RDF::Repository.new                                  # summary graph
    loadRDF graph: fullGraph                                         # load graph
    saveRDF fullGraph if basename&.index('msg.') == 0                # cache RDF extracted from nonRDF
    treeFromGraph(fullGraph).map{|subject, resource|                 # resources to summarize
      subject = subject.R                                            # subject resource
      full = (resource[Type]||[]).find{|t| NoSummary.member? t}      # resource types retaining full content
      predicates = [Abstract, Audio, Creator, Date, Image, W3 + 'ldp#contains',
                    DC + 'identifier', Title, To, Type, Video, Schema + 'itemListElement']
      predicates.push Content if full                                # main content sometimes included in preview
      predicates.push Link unless subject.host                       # include untyped links in local content
      predicates.map{|predicate|                                     # summary predicate
        if o = resource[predicate]
          (o.class == Array ? o : [o]).map{|o|                       # summary object(s)
            miniGraph << RDF::Statement.new(subject,predicate.R,o) unless o.class == Hash} # summary triple
        end} if [Image,Abstract,Title,Link,Video].find{|p|resource.has_key? p} || full} # if summary data exists

    summary.writeFile miniGraph.dump(:turtle,base_uri: self,standard_prefixes: true) # cache summary
    summary                                                          # return summary
  end

  # MIME type, data -> Repository
  def readRDF format, content, graph
    return if content.empty?
    case format                                                    # content type:
    when /octet.stream/                                            #  blob
    when /^audio/                                                  #  audio
      audio_triples graph
    when /^image/                                                  #  image
      graph << RDF::Statement.new(self, Type.R, Image.R)
      graph << RDF::Statement.new(self, Title.R, basename)
    when /^video/                                                  #  video
      graph << RDF::Statement.new(self, Type.R, Video.R)
      graph << RDF::Statement.new(self, Title.R, basename)
    else
      if reader ||= RDF::Reader.for(content_type: format)          # find reader

        reader.new(content, base_uri: self){|_|graph << _}         # read RDF

        if format == 'text/html' && reader != RDF::RDFa::Reader    # read RDFa
          RDF::RDFa::Reader.new(content, base_uri: self){|g|
            g.each_statement{|statement|
              if predicate = Webize::MetaMap[statement.predicate.to_s]
                next if predicate == :drop
                statement.predicate = predicate.R
              end
              graph << statement }} rescue (logger.debug "⚠️ RDFa::Reader failure #{uri}")
        end
      else
        logger.warn ["⚠️ no RDF reader for " , format].join # reader not found
      end
    end    
  end

  # Repository -> 🐢 file(s)
  def saveRDF repository = nil
    return self unless repository || env[:repository]                # repository to store

    timestamp = RDF::Query::Pattern.new :s, Date.R, :o               # timestamp query-pattern
    creator = RDF::Query::Pattern.new :s, Creator.R, :o              # sender query-pattern
    to = RDF::Query::Pattern.new :s, To.R, :o                        # receiver query-pattern
    type = RDF::Query::Pattern.new :s, Type.R, :o                    # RDF type query-pattern

    (repository || env[:repository]).each_graph.map{|graph|          # graph
      g = graph.name ? (graph.name.R env) : graphURI                 # graph URI
      f = [g.document, :🐢].join '.'                                 # 🐢 location
      log = []

      unless File.exist? f
        RDF::Writer.for(:turtle).open(f){|f|f << graph}              # save 🐢
        env[:updates] << graph if env.has_key? :updates
        log << ["\e[38;5;48m#{graph.size}⋮🐢\e[1m", [g.display_host, g.path, "\e[0m"].join] unless g.in_doc?
      end

      # if location isn't on timeline, link to timeline. TODO additional indexing. ref https://pdsinterop.org/solid-typeindex-parser/ https://github.com/solid/solid/blob/main/proposals/data-discovery.md#type-index-registry
      if !g.to_s.match?(HourDir) && (ts = graph.query(timestamp).first_value) && ts.match?(/^\d\d\d\d-/)

        t = ts.split /\D/                                            # split timestamp
        🕒 = [t[0..3], t.size < 4 ? '0' : nil, [t[4..-1],            # timeline containers
               ([g.slugs, [type, creator, to].map{|pattern|          # name tokens from graph and query pattern
                   slugify = pattern==type ? :display_name : :slugs  # slug verbosity
                   graph.query(pattern).objects.map{|o|              # query for slug-containing triples
                  o.respond_to?(:R) ? o.R.send(slugify) : o.to_s.split(/[\W_]/)}}]. # tokenize
                  flatten.compact.map(&:downcase).uniq - BasicSlugs)].          # apply slug skiplist
                compact.join('.')[0..125].sub(/\.$/,'')+'.🐢'].compact.join '/' # 🕒 path

        unless File.exist? 🕒
          FileUtils.mkdir_p File.dirname 🕒                          # create timeline container(s)
          FileUtils.ln f, 🕒 rescue FileUtils.cp f, 🕒               # hardlink 🐢 to 🕒, fallback to copy
          log.unshift [:🕒, ts] unless g.in_doc?
        end
      end
      logger.info log.join ' ' unless log.empty?}
    self
  end

  # Repository -> {s -> p -> o} tree
  def treeFromGraph graph = nil
    graph ||= env[:updates] || env[:repository]
    return {} unless graph
    tree = {}    # output tree
    inlined = [] # inlined-node list

    graph.each_triple{|subj,pred,obj| # walk graph
#     puts [subj,pred,obj].join ' '   # inspect triples

      s = subj.to_s                   # subject URI
      p = pred.to_s                   # predicate URI
      blank = obj.class == RDF::Node  # bnode?
      if blank || p == 'http://www.w3.org/ns/ldp#contains' # bnode or child-node?
        o = obj.to_s                  # object URI
        inlined.push o                # inline object
        obj = tree[o] ||= blank ? {} : {'uri' => o}
      end
      tree[s] ||= subj.class == RDF::Node ? {} : {'uri' => s} # subject
      tree[s][p] ||= []                                       # predicate
      tree[s][p].push obj                                     # object
    }
    inlined.map{|n|tree.delete n} # sweep inlined nodes from index
    tree
  end
end

RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl] # enable 🐢 suffix for turtle files

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
