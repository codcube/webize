module Webize
  module HTML

    FeedIcon = Webize.configData 'style/icons/feed.svg'
    HostColor = Webize.configHash 'style/color/host'
    Icons = Webize.configHash 'style/icons/map'
    ReHost = Webize.configHash 'hosts/UI'
    SiteFont = Webize.configData 'style/fonts/hack.woff2'
    SiteIcon = Webize.configData 'style/icons/favicon.ico'
    StatusColor = Webize.configHash 'style/color/status'
    StatusColor.keys.map{|s|
      StatusColor[s.to_i] = StatusColor[s]}

    # a few layers to serializing to HTML.
    # First, the graph is turned into a tree of JSON-compatible nested Hash objects. the JSON#fromGraph
    # implementation is in JSON.rb as we also use this treeization for other formats, RSS and JSON.
    # the tree is first indexed on subject URI, returning a resource and its data, indexed on predicate URI,
    # to an array of objects with blank and/or contained nodes inlined where predicate indexing begins anew

    # example: {subjectURI -> {predicateURI -> ['object', 234, {predicateURI -> [...]}]}}

    # We came up with this format before Ruby had an RDF library, when we knew we didn't want to write one
    # if we could get away with using a subset of RDF in JSON and piggyback on existing fast serializers/parsers.
    # with good handling of recursive blank nodes there's not much missing aside from value types not supported by JSON,
    # primarily <URI>. we use reserved key 'uri' for the resource identifier. if that's missing, it's a blank node.

    # We churn through the toplevel index and hand each resource to its type-specific markup function, or a generic handler.
    # we know everything has been rendered since any node not in the index was inlined and recursive renderers will hit it
    # Markup lambdas emit again JSON-compatible nested Hash representation of DOM nodes, trivially serializable into HTML

    class Writer < RDF::Writer

      format Format

      def initialize(output = $stdout, **options, &block)

        @graph = RDF::Graph.new
        @base = RDF::URI(options[:base_uri]) if options[:base_uri]

        super do
          block.call(self) if block_given?
        end
      end

      def write_triple(subject, predicate, object)
        statement = RDF::Statement.new(subject, predicate, object)
        @graph.insert(statement)
      end

      def write_epilogue
        @output.write HTML.render Markup[Schema + 'Document'][JSON.fromGraph(@graph), @base.env]
      end

    end

    # Ruby value -> Markup
    def self.markup o, env
      case o
      when Array              # Array
        o.map{|n| markup n, env}
      when FalseClass         # boolean
        {_: :input, type: :checkbox}
      when Hash               # Hash
        Markup[o[Type] &&
               o[Type].map(&:to_s).find{|t|Markup[t]} ||
               BasicResource][o, env]
      when Integer
        o
      when NilClass
        o
      when RDF::Literal       # RDF literal
        if [RDF.HTML, RDF.XMLLiteral].member? o.datatype
          o.to_s              # HTML
        else                  # String
          CGI.escapeHTML o.to_s
        end
      when RDF::URI           # RDF::URI
        o = Resource.new(o).env env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when String             # String
        CGI.escapeHTML o
      when Time               # Time
        Markup[Date][o, env]
      when TrueClass          # boolean
        {_: :input, type: :checkbox, checked: true}
      when Webize::Resource   # Resource
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when Webize::URI        # URI
        o = Resource.new(o).env env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      else                    # default
        puts "markup undefined for #{o.class}"
        {_: :span, c: CGI.escapeHTML(o.to_s)}
      end
    end

    # Markup -> HTML
    def self.render x
      case x
      when Array
        if x.empty?
          ''
        else
          render(x.first) + render(x.rest)
        end
      when Hash

        void = [:img, :input, :link, :meta].member? x[:_]

        '<' + (x[:_] || 'div').to_s +                        # open tag
          (x.keys - [:_,:c]).map{|a|                         # attr name
          ' ' + a.to_s + '=' + "'" + x[a].to_s.chars.map{|c| # attr value
            {"'"=>'%27', '>'=>'%3E', '<'=>'%3C'}[c]||c}.join + "'"}.join +
          (void ? '/' : '') + '>' + (render x[:c]) +         # child nodes
          (void ? '' : ('</'+(x[:_]||'div').to_s+'>'))       # close

      when NilClass
        ''
      when String
        x
      else
        CGI.escapeHTML x.to_s
      end
    end
  end
end
