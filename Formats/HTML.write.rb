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

    class Property < Resource # representation of attribute/edge/field/key/predicate/property

      def markup content       # property URI -> representation generator method
        if Markup.has_key? uri # typeed render
          send Markup[uri], content
        else                   # generic render
          content.map{|v|
            HTML.markup v, env}
        end
      end

    end

    class Node < Resource # representation of node/object/resource/thing

      def self.markup o, env # type URI -> representation generator method
        Node.new(env[:base]).env(env).        # representation instance
          send o[Type] &&                     # has RDF type attribute?
               Markup[o[Type].map{|t|
                        t.class == Hash ? t['uri'] : t.to_s}.find{|t| # types
                        Markup.has_key? t}] || # typed render
               :resource, o                    # generic render
      end

      # construct and call a property renderer
      def property p, o
        Property.new(p).env(env).markup o
      end

    end

    # OUT dataflow
    # class --method-->

    # RDF::Graph --JSON#fromGraph-->
    # RDF representation in Ruby values --Node/Property#markup-->
    # DOM-node representation in Ruby values --Writer#render-->
    # HTML --Protocols-->
    # message receiver (User Agent, client, method caller)

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
          id = o.__id__
          if env[:fragments].has_key? id # existing representation
            if uri = o['uri']            # identified?
              uri = Webize::Resource uri, env # global reference
              {_: :a, href: '#' + uri.local_id, c: uri.display_name} # local (in-doc) reference
            else
              nil # can't link to blank node - no identifier available
            end
          else
            env[:fragments][id] = true
            HTML::Node.markup o, env # new representation
          end
        end
      when Integer
        o
      when NilClass
        o
      when RDF::Graph # show all nodes reachable from base URI <https://www.w3.org/submissions/CBD/> <https://patterns.dataincubator.org/>
        graph = JSON.fromGraph(o)[env[:base]] || {} # graph data
        graph[Type] = [Document]                    # type as graph document
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
