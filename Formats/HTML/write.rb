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
    VoidElement = Webize.configList('HTML/void').map{|e| e.to_sym }

    # representation of attribute aka edge aka field aka key aka predicate aka property

    class Property < Resource

      # URI -> method table
      Markup = Webize.configHash 'HTML/property'

      # property URI -> representation generator method mapper
      def markup content
        if Markup.has_key? uri # typed render
          send Markup[uri], content
        else                   # generic render
          content.map{|v|
            HTML.markup v, env}
        end
      end

    end

    # representation of node aka object aka resource aka thing

    class Node < Resource

      # URI -> method table
      Markup = Webize.configHash 'HTML/resource'

      # resource-type URI -> representation generator method mapper
      def self.markup o, env
        Node.new(env[:base]).env(env).        # representation instance
          send o[Type] &&                     # has RDF type attribute?
               Markup[o[Type].map{|t|
                        t.class == Hash ? t['uri'] : t.to_s}.find{|t| # types
                        Markup.has_key? t}] || # typed render
               :resource, o                    # generic render
      end

      # construct and call a renderer in current output context
      def property p, o
        Property.new(p).env(env).markup o
      end

    end

    class Writer < RDF::Writer

      # OUT dataflow
      # class              --method-->

      # RDF::Graph         --JSON#fromGraph-->
      # RDF representation --Node#markup--> and --Property#markup-->
      # DOM representation --Writer#render-->
      # HTML               --Protocols-->
      # message receiver: caller, client, User Agent

      # "RDF representation" is our native representation in ruby values, see <JSON.rb> for documentation

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

    def self.cachestamp html, baseURI              # input doc, base-URI
      doc = Nokogiri::HTML.parse html              # parse doc
      if head = doc.css('head')[0]                 # has head?
        base = head.css('base[href]')[0]           # find base node
        return html if base                        # nothing to do
      else                                         # headless?
        Console.logger.warn "⚠️ !head #{baseURI}"  # warn
        head = Nokogiri::XML::Node.new 'head', doc # create head
        if body = doc.css('body')[0]
          body.before head                         # attach head
        else
          doc.add_child head
        end
      end
      base = Nokogiri::XML::Node.new 'base', doc   # create base node
      base['href'] = baseURI                       # set base-URI
      head.add_child base                          # attach base node
      doc.to_html                                  # output doc
    end

    # markup-generator for all Ruby types
    def self.markup o, env
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
          # loop-elimination and deduplication:
          # point to in-doc representation of fragment on subsequent calls
          id = o.__id__
          if env[:fragments].has_key? id                # existing representation?
            if uri = o['uri']                           # identified?
              uri = Webize::Resource uri, env           # global identifier
              [{_: :a, href: '#' + (uri.local_id||''),  # local representation identifier
                class: :fragref, c: :↜}, ' ']          # representation reference
            else
              nil                                       # blank node (no identifier)
            end
          else
            env[:fragments][id] = true
            HTML::Node.markup o, env                    # representation
          end
        end
      when Integer
        o
      when NilClass
        o
      when Webize::Resource # above RDF::URI because RDF::URI === Webize::Resource('base',{})
        #puts o, caller[0..14] if o.dataURI? || o.imgPath?
        {_: :a, href: o.href, c: o.imgPath? ? {_: :img, src: o.href} : o.display_name}
      when RDF::Graph
        # markup nodes visible via reference from base. this is broader than a concise bounded description: <https://www.w3.org/submissions/CBD/> <https://patterns.dataincubator.org/>
        graph = JSON.fromGraph(o)[env[:base]] || {} # graph to tree, rooted at base URI
        graph[Type] = [Document]                    # type graph as document
        markup graph, env                           # markup document
      when RDF::Repository
        :repository
      when RDF::Literal
        if [RDF.HTML, RDF.XMLLiteral].member? o.datatype
          o.to_s
        else
          {_: :span, c: (CGI.escapeHTML o.to_s)}
        end
      when RDF::URI
        markup Webize::Resource(o, env), env
      when String
        CGI.escapeHTML o
      when Time
        Property.new(Date).env(env).markup o
      when TrueClass
        {_: :input, type: :checkbox, checked: true}
      when Webize::URI
        markup Webize::Resource(o, env), env
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

        void = VoidElement.member? x[:_]

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
