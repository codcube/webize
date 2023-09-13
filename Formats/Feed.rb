# coding: utf-8
module Webize
  module Feed

    Extensions = %w(
.atom
.rss
.xml
)
    Names = %w(
atom atom.xml
feed feed.xml
index.xml
rss rss.xml
)
    Subscriptions = {} # hostname -> [feedURL,..]

    class Format < RDF::Format
      content_type 'application/rss+xml',
                   extensions: [:atom, :rss, :rss2, :xml],
                   aliases: %w(
                   application/atom+xml;q=0.8
                   application/x-rss+xml;q=0.2
                   application/xml;q=0.2
                   text/atom;q=0.2
                   text/xml;q=0.2)

      content_encoding 'utf-8'

      reader { Reader }

      def self.symbols
        [:atom, :feed, :rss]
      end
    end

    class Reader < RDF::Reader
      format Format

      Atom = 'http://www.w3.org/2005/Atom#'
      RSS = 'http://purl.org/rss/1.0/'

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @base = options[:base_uri]
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
        map_predicates(:raw_triples){|s,p,o|
          fn.call RDF::Statement.new((s = Webize::URI.new(s)), Webize::URI.new(p),
                                     p == Content ? ((l = RDF::Literal(Webize::HTML.format o.to_s, @base)).datatype = RDF.HTML
                                                     l) : o,
                                     graph_name: s)}
      end

      def map_predicates *f
        send(*f){|s,p,o|
          p = MetaMap[p] if MetaMap.has_key? p # map to predicate URI
          o = Webize.date o if p.to_s == Date  # normalize date format
          unless p == :drop
            logger.warn ['no RDF predicate found:', p, o].join ' ' unless p.match? /^https?:/
            yield s, p, o
          end}
      end

      def raw_triples
        # identifier patterns
        reRDFabout = /about=["']?([^'">\s]+)/         # RDF @about
        reLink = /<link>([^<]+)/                      # <link> element
        reLinkCData = /<link><\!\[CDATA\[([^\]]+)/    # <link> CDATA block
        reLinkHref = /<link[^>]+rel=["']?alternate["']?[^>]+href=["']?([^'">\s]+)/ # <link> @href @rel=alternate
        reLinkRel = /<link[^>]+href=["']?([^'">\s]+)/ # <link> @href
        reOrigLink = /<feedburner:origLink>([^<]+)/   # <feedburner:origLink> element
        reId = /<(?:gu)?id[^>]*>([^<]+)/              # <id> element
        reKey = /<Key>([^<]+)/                        # <Key> element
        isURL = /\A(\/|http)[\S]+\Z/                  # HTTP URI

        # (SG|X)ML element-patterns
        isCDATA = /^\s*<\!\[CDATA/m
        reCDATA = /^\s*<\!\[CDATA\[(.*?)\]\]>\s*$/m
        reElement = %r{<([a-z0-9]+:)?([a-z]+)([\s][^>]*)?>(.*?)</\1?\2>}mi
        reGroup = /<\/?media:group>/i
        reHead = /<(rdf|rss|feed)([^>]+)/i
        reItem = %r{<(?<ns>rss:|atom:)?(?<tag>item|entry)(?<attrs>[\s][^>]*)?>(?<inner>.*?)</\k<ns>?\k<tag>>}mi
        reItem = %r{<(?<ns>)?(?<tag>Contents)(?<attrs>)?>(?<inner>.*?)</Contents>}mi if @doc.match? %r{<[^>]+>\n?<ListBucketResult}mi
        reMedia = %r{<(link|enclosure|media)([^>]+)>}mi
        reSrc = /(href|url|src)=['"]?([^'">\s]+)/
        reRel = /rel=['"]?([^'">\s]+)/
        reXMLns = /xmlns:?([a-z0-9]+)?=["']?([^'">\s]+)/

        # build XML namespace table
        x = {}
        head = @doc.match(reHead)
        head && head[2] && head[2].scan(reXMLns){|m|
          prefix = m[0]
          base = m[1]
          base = base + '#' unless %w{/ #}.member? base [-1]
          x[prefix] = base}

        # scan items
        @doc.scan(reItem){|m|
          attrs = m[2]
          inner = m[3]

          # identifier search
          if id = (attrs && attrs.match(reRDFabout) ||
                   inner.match(reOrigLink) ||
                   inner.match(reLink) ||
                   inner.match(reLinkCData) ||
                   inner.match(reLinkHref) ||
                   inner.match(reLinkRel) ||
                   inner.match(reId) ||
                   inner.match(reKey)
                  ).yield_self{|capture|
               capture && capture[1]}

            subject = Webize::URI.new @base.join id
            subject.query = nil if subject.query&.match?(/utm[^a-z]/)
            subject.fragment = nil if subject.fragment&.match?(/utm[^a-z]/)
            reddit = subject.host&.match /reddit.com$/
            # type tag
            yield subject, Type,
                  if subject.host == 'www.youtube.com'
                    Video
                  elsif subject.imgPath?
                    Image
                  else
                    Post
                  end.R

            # addressee/recipient/destination group
            to = reddit ? ('https://www.reddit.com/' + subject.parts[0..1].join('/')).R : @base
            yield subject, To, to

            # media links
            inner.scan(reMedia){|e|
              if url = e[1].match(reSrc)
                rel = e[1].match reRel
                rel = rel ? rel[1] : 'link'
                o = Webize::URI.new(@base.join CGI.unescapeHTML(url[2]))
                o.path ||= '/'
                p = case File.extname o.path
                    when /jpg|png|webp/i
                      Image
                    else
                      Atom + rel
                    end
                yield subject, p, o unless subject == o # emit link unless self-referential
              end}

            # process XML elements
            inner.gsub(reGroup,'').scan(reElement){|e|
              p = (x[e[0] && e[0].chop]||RSS) + e[1] # expand node name to attribute URI
              if [Atom+'id', RSS+'link', RSS+'guid', RSS+'Key', Atom+'link'].member? p
              # subject URI element
              elsif p == RSS + 'ETag'
                yield subject, Title, subject.basename || subject.host
              elsif [Atom+'author', RSS+'author', RSS+'creator', 'http://purl.org/dc/elements/1.1/creator'].member? p
                # creators
                crs = []
                # XML name + URI
                uri = e[3].match /<uri>([^<]+)</
                name = e[3].match /<name>([^<]+)</
                crs.push uri[1].R if uri
                crs.push name[1] if name && !(uri && (uri[1].R.path||'/').sub('/user/','/u/') == name[1])
                unless name || uri
                  crs.push e[3].yield_self{|o|
                    case o
                    when isURL
                      o.R
                    when isCDATA
                      o.sub reCDATA, '\1'
                    else
                      o
                    end}
                end
                # author(s) -> RDF
                crs.map{|cr|yield subject, Creator, cr}
              else # element -> RDF
                yield subject, p, e[3].yield_self{|o| # unescape
                  case o
                  when isCDATA
                    o.sub reCDATA, '\1'
                  when /</m
                    o
                  else
                    CGI.unescapeHTML o
                  end
                }.yield_self{|o|                      # map datatypes
                  if o.match? isURL
                    o.R
                  elsif reddit && p == Atom+'title'
                    o.sub /\/u\/\S+ on /, ''
                  else
                    o
                  end}
              end
            }
          end}
      end
    end
    class Document < Resource
      def write graph={}
        HTML.render ['<?xml version="1.0" encoding="utf-8"?>',
                     {_: :feed,xmlns: 'http://www.w3.org/2005/Atom',
                      c: [{_: :id, c: uri},
                          {_: :title, c: uri},
                          {_: :link, rel: :self, href: uri},
                          {_: :updated, c: Time.now.iso8601},
                          graph.map{|u,d|
                            {_: :entry,
                             c: [{_: :id, c: u}, {_: :link, href: u},
                                 d[Date] ? {_: :updated, c: d[Date][0]} : nil,
                                 d[Title] ? {_: :title, c: d[Title]} : nil,
                                 d[Creator] ? {_: :author, c: d[Creator][0]} : nil,
                                 {_: :content, type: :xhtml,
                                  c: {xmlns:"http://www.w3.org/1999/xhtml",
                                      c: d[Content]}}]}}]}]
      end
    end
  end
end
