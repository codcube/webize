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

    Schema = 'http://mw.logbook.am/webize#'

    Child, Name, Node, Sibling = [Schema + 'child',
                                  Schema + 'name',
                                  Schema + 'Node',
                                  Schema + 'sibling']

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
        return if o.empty?
        types = (o[Type]||[]).map{|t|
          MetaMap[t.to_s] || t.to_s} # map to renderable type
        seen = false
        [types.map{|type|     # type tag(s)
          if f = Markup[type] # renderer defined for type?
            seen = true       # mark as rendered
            f[o,env]          # render specific resource type
          end},               # render generic resource
         (Markup[BasicResource][o, env] unless seen)]
      when Integer
        o
      when RDF::Literal
        if [RDF.HTML, RDF.XMLLiteral].member? o.datatype
          if env[:proxy_refs] # proxy references
            resolve_hrefs o.to_s, env
          else
            o.to_s            # HTML literal
          end
        else                  # String literal
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
