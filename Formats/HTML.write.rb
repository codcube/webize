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

    # representation of attribute/edge/field/key/predicate/property
    class Property < Resource
      def markup content # dispatch on property URI to representation generator method
        if Markup.has_key? uri # type-specific renderer
          send Markup[uri], content
        else                   # generic renderer
          content.map{|v|
            HTML.markup v, env}
        end
      end
    end

    # representation of node/object/resource/thing
    class Node < Resource
      def self.markup o, env # dispatch on type URI to representation generator method
        Node.new(env[:base]).env(env).        # representation instance
          send o[Type] &&                     # has RDF type attribute?
               Markup[o[Type].map(&:to_s).find{|t| # types
                   Markup.has_key? t}] ||     # typed renderer found?
               :resource, o                   # generic renderer
      end
    end

    # OUTPUT dataflow:

    # RDF graph ->
    #   JSON (s,p,o) tree ->
    #     HTML "markup" representation tree ->
    #       HTML string

    # the RDF graph is transformed to a tree of JSON-compatible nested Hash objects in JSON#fromGraph,
    # implemented in JSON.rb as we also use treeization for rendering RSS and JSON.
    # the datastructure is indexed on subject URI, returning a resource and its data, indexed on predicate URI,
    # to an array of objects with blank and/or contained nodes inlined where predicate indexing begins anew

    # example: {subjectURI -> {predicateURI -> ['object', 234, {predicateURI -> [...]}]}}

    # We came up with this format before Ruby had an RDF library, when we knew we didn't want to write one
    # if we could get away with using a subset of RDF in JSON and piggyback on existing fast serializers/parsers.
    # with good handling of recursive blank nodes there's not much missing aside from datatypes not supported by JSON,
    # primarily <URI>. we use reserved key 'uri' for a resource's identifier. if that's missing, it's a blank node.

    # Resources and their properties can be associated with type-specific markup methods (w/ defaults in HTML.templates.rb),
    # which emit representations of DOM nodes / HTML elements, again in a JSON-compatible nested Hash for composability and
    # layering with RDF-unaware and generic JSON tools and trivial serializability to HTML

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
        @output.write HTML.render (HTML.markup @graph, @base.env)
      end

    end

    # value -> Markup
    def self.markup o, env
      # can we use new Ruby pattern-matching features to define each of these separately? TODO investigate
      case o
      when Array
        o.map{|_|
          markup _, env}
      when FalseClass
        {_: :input, type: :checkbox}
      when Hash
        HTML::Node.markup o, env
      when Integer
        o
      when NilClass
        o
      when RDF::Graph
        markup JSON.fromGraph(o), env
      when RDF::Repository
        :repository
      when RDF::Literal
        if [RDF.HTML, RDF.XMLLiteral].member? o.datatype
          o.to_s
        else
          CGI.escapeHTML o.to_s
        end
      when RDF::URI
        o = Resource.new(o).env env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when String
        CGI.escapeHTML o
      when Time
        Webize::HTML::Property(Date, env).markup o
      when TrueClass
        {_: :input, type: :checkbox, checked: true}
      when Webize::Resource
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when Webize::URI
        o = Resource.new(o).env env
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      else
        puts "⚠️ markup undefined for type #{o.class}"
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
            {"'"=>'%27', '>'=>'%3E', '<'=>'%3C'}[c]||c}.join + "'"}.join + # TODO faster / more complete escaping?
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
