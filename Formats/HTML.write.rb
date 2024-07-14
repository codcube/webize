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
        if uri = o['uri']
          uri = Webize::Resource uri, env
          if env[:displayed].has_key? uri # reference to in-doc representation
            return {_: :a, href: '#' + uri.local_id, c: uri.display_name}
          else                            # mark as displayed
            env[:displayed][uri] = true
          end

        end
        Node.new(env[:base]).env(env).        # representation instance
          send o[Type] &&                     # has RDF type attribute?
               Markup[o[Type].map{|t|
                        t.class == Hash ? t['uri'] : t.to_s}.find{|t| # types
                        Markup.has_key? t}] || # typed renderer found?
               :resource, o                    # generic render
      end

      # construct and call property renderer
      def property p, o
        Property.new(p).env(env).markup o
      end

    end

    # OUTPUT dataflow:

    # RDF::Graph --JSON#fromGraph--> RDF representation in Ruby values --Node/Property#markup-->
    # DOM-node representation in Ruby values --Writer#render--> HTML --Protocols--> message receiver

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

    # markup-generation function for any type. is there a clean way to add #markup to every class or is that monkey-patching/namespace-pollution?
    def self.markup o, env
      # can we use Ruby pattern-matching features to define each of these separately?
      case o
      when Array
        o.map{|_|
          markup _, env}
      when FalseClass
        {_: :input, type: :checkbox}
      when Hash
        if o.keys == %w(uri)
          markup (RDF::URI o['uri']), env
        else
          HTML::Node.markup o, env
        end
      when Integer
        o
      when NilClass
        o
      when RDF::Graph # render all nodes reachable from base <https://www.w3.org/submissions/CBD/> <https://patterns.dataincubator.org/>
        graph = JSON.fromGraph(o)[env[:base]] || {} # RDF -> JSON
        graph[Type] = [DOMnode + 'html']            # type as HTML document
        markup graph, env                           # markup graph document
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
        Property.new(Date).env(env).markup o
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
