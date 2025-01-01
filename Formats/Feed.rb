# coding: utf-8
module Webize
  class URI

    def RSS_available?
      RSS_hosts.member?(host) &&
        !(path||'').index('.rss') &&
        !%w(gallery media).member?(parts[0])
    end

  end
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
    Subscriptions = {} # hostname -> [feed URI, ..]

    # contruct subscription list
    def self.subscribe host
      names = Webize.configList 'subscriptions/' + host # tokenize slugs
      uris = names.map{|slug| yield slug }              # emit slug to URI-template block

      Subscriptions[host] = uris                        # subscriptions
    end

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
      writer { Writer }

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
        @options = options
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
        map_predicates(:raw_triples){|s, p, o, graph = @base|
          fn.call RDF::Statement.new(s, Webize::URI.new(p), o,
                                     graph_name: graph)}
      end

      def map_predicates *f
        send(*f){|s, p, o, graph|

          p = MetaMap[p] if MetaMap.has_key? p # map to predicate URI

          o = Webize.date o if p.to_s == Date  # normalize date format
          o = Webize::Resource(o, @base.env).relocate if o.class == Webize::URI && o.relocate? # relocate object URI

          unless p == :drop
            logger.warn ['no RDF predicate found:', p, o].join ' ' unless p.match? /^https?:/
            yield s, p, o, graph
          end}
      end

      def raw_triples &f
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
        isEHTML = /^[^<>]*(&lt;[^<>]*&gt;|&amp;([a-z+]|#\d+);)[^<>]*$/m # escaped HTML: escaped <> or doubly-escaped entity in absence of any <>
        isHTML = /<[^>]+>|&([a-z+]|#\d+);/m                             # regular HTML: presence of any <> or HTML entity
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

            # subject
            subject = Webize::URI.new @base.join id
            subject.query = nil if subject.query&.match?(/utm[^a-z]/)
            subject.fragment = nil if subject.fragment&.match?(/utm[^a-z]/)

            # graph
            graph = subject.graph
            yield graph, Contains, subject

            # type tag
            yield subject, Type,
                  Webize::URI(if subject.host == 'www.youtube.com'
                           Video
                          elsif subject.imgPath?
                            Image
                          else
                            Post
                           end), graph

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
                yield subject, p, o, graph
              end}

            # generic SGML/XML node
            inner.gsub(reGroup,'').scan(reElement){|e| # parse node to (prefix, name, content) tuple
              p = (x[e[0] && e[0].chop] || RSS) + e[1] # map optionally-prefixed node name to attribute URI
              o = e[3]                                 # node content

              o = o.sub reCDATA, '\1' if o.match? isCDATA # unwrap CDATA
              o = CGI.unescapeHTML o if o.match? isEHTML # unescape HTML

              o = case o                               # object datatype
                  when isURL
                    Webize::URI o
                  when isHTML
                    HTML::Reader.new(o, base_uri: graph).scan_fragment &f
                  else
                    o
                  end

              yield subject, p, o, graph
            }
          end}
      end
    end
    class Writer < RDF::Writer

      format Format

      def initialize(output = $stdout, **options, &block)
        @graph = RDF::Graph.new
        super do
          block.call(self) if block_given?
        end
      end

      def write_triple(subject, predicate, object)
        @graph.insert RDF::Statement.new(subject, predicate, object)
      end

      def write_epilogue
        @output.write HTML.render ['<?xml version="1.0" encoding="utf-8"?>',
                                   {_: :feed,xmlns: 'http://www.w3.org/2005/Atom',
                                    c: [{_: :id, c: uri},
                                        {_: :title, c: uri},
                                        {_: :link, rel: :self, href: uri},
                                        {_: :updated, c: Time.now.iso8601},
                                        JSON.fromGraph(@graph).map{|u,d|
                                          {_: :entry,
                                           c: [{_: :id, c: u}, {_: :link, href: u},
                                               d[Date] ? {_: :updated, c: d[Date][0]} : nil,
                                               d[Title] ? {_: :title, c: d[Title]} : nil,
                                               d[Creator] ? {_: :author, c: d[Creator][0]} : nil,
                                               {_: :content, type: :xhtml,
                                                c: {xmlns:"http://www.w3.org/1999/xhtml",
                                                    c: d[Contains]}}]}}]}]
      end
    end
  end
end
