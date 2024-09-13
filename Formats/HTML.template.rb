require_relative 'HTML.template.document.rb' # document template
require_relative 'HTML.template.resource.rb' # resource template

module Webize                                # templates
  module HTML
    class Property
 
      # property-markup methods

      def abstract as
        {class: :abstract,
         c: as.map{|a| [(HTML.markup a, env), ' ']}}
      end

      def buttons resources
        [{_: :style, c: "a.button {background-color: ##{Digest::SHA2.hexdigest(uri)[0..5]}; color: white}"},

         resources.map{|r|
           uri = Webize::Resource r['uri'], env

           {_: :a,
            href: uri.href,
            id: 'b' + Digest::SHA2.hexdigest(rand.to_s),
            class: :button,
            c: uri.display_name}}]
      end

      def cache locations
        locations.map{|l|
          {_: :a, href: '/' + l.fsPath, c: :📦}}
      end

      def creator creators
        creators.map{|creator|
          if Identifiable.member? creator.class
            uri = Webize::Resource.new(creator).env env
            name = uri.display_name
            color = Digest::SHA2.hexdigest(name)[0..5]
            {_: :a, class: :from, href: uri.href, style: "background-color: ##{color}", c: name}
          else
            HTML.markup creator, env
          end}
      end

      # graph index - we're adding triples at a late stage just before rendering. to use these pointers via Turtle, we'll want a 'graph annotation pass' eventually
      def graph_index nodes

        nodes.map{|node|
          # for remote graphs,
          next unless uri = node['uri']
          uri = Webize::Resource uri, env
          next unless uri.host

          # add pointers to upstream, cached (TODO historical) versions
          node.update({'#cache' => [POSIX::Node(uri)],
                       '#origin' => [uri],
                      })}

        index_table nodes
      end

      def identifier uris
        (uris.class == Array ? uris : [uris]).map{|uri|
          {_: :a, c: :🔗,
           href: env ? Webize::Resource(uri, env).href : uri,
           id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}
      end

      # table of nodes without an inlined display of their full content
      # as w/ #graph_index we may create pointers to e.g. in-doc representations
      def index_table(nodes) = table nodes, skip: [Contains]

      def origin locations
        locations.map{|l|
          {_: :a, href: l.uri, c: :↗, class: :origin, target: :_blank}}
      end

      def rdf_type types
        types.map{|t|
          t = Webize::Resource t.class == Hash ? t['uri'] : t, env
          {_: :a, class: :type, href: t.href,
           c: if t.uri == Contains
            nil
          elsif Icons.has_key? t.uri
            Icons[t.uri]
          else
            t.display_name
           end}}
      end

      def table graph, skip: []
        case graph.size
        when 0 # empty
          nil
#        when 1 # key/val render of resource
#          Node.new(env[:base]).env(env).keyval graph[0], skip: skip
        else   # tabular render of resources
          keys = graph.map(&:keys).flatten.uniq -
                 skip                        # apply property skiplist

          {_: :table, class: :tabular,       # table
           c: [({_: :thead,
                 c: {_: :tr, c: keys.map{|p| # table heading
                       p = Webize::URI(p)
                       slug = p.display_name
                       icon = Icons[p.uri] || slug
                       [{_: :th,             # ☛ sorted columns
                         c: {_: :a, c: icon,
                             href: URI.qs(env[:qs].merge({'sort' => p.uri,
                                                          'order' => env[:order] == 'asc' ? 'desc' : 'asc'}))}}, "\n"]}}} if env),
               {_: :tbody,
                c: graph.map{|resource|      # resource -> row
                  [{_: :tr, c: keys.map{|k|
                      [{_: :td, property: k,
                        c: if resource.has_key? k
                         Property.new(k).env(env).markup resource[k]
                        end},
                       "\n" ]}}, "\n" ]}}]}
        end
      end

      def title titles
        titles.map{|t|
          {_: :span, c: HTML.markup(t, env)}}
      end

      def to recipients
        recipients.map{|r|
          if Identifiable.member? r.class
            uri = Webize::Resource.new(r).env env
            name = uri.display_name
            color = Digest::SHA2.hexdigest(name)[0..5]
            {_: :a, class: :to, href: uri.href, style: "background-color: ##{color}", c: ['&rarr;', name].join}
          else
            HTML.markup r, env
          end}
      end
    end

    class Node

      TabularChild = %w(head ol ul) # display children in tabular format

      # markup methods

      # basic DOM nodes - parameterize generic renderer with name
      def head(node) = resource node, :head

      def ul(node) = resource node, :ul
      def ol(node) = resource node, :ol
      def li(node) = resource node, :li

      def h1(node) = resource node, :h1
      def h2(node) = resource node, :h2
      def h3(node) = resource node, :h3
      def h4(node) = resource node, :h4
      def h5(node) = resource node, :h5
      def h6(node) = resource node, :h6

      def table(node) = resource node, :table
      def thead(node) = resource node, :thead
      def tfoot(node) = resource node, :tfoot

      def th(node) = resource node, :th
      def tr(node) = resource node, :tr
      def td(node) = resource node, :td

      # anchor
      def a _
        _.delete Type

        if content = (_.delete Contains)
          content.map!{|c|
            HTML.markup c, env}
        end

        links = _.delete Link

        if title = (_.delete Title)
          title.map!{|c|
            HTML.markup c, env}
        end

        attrs = keyval _ unless _.empty? # remaining attributes

        links.map{|ref|
          ref = Webize::URI(ref['uri']) if ref.class == Hash
          [{_: :a, href: ref,
            class: ref.host == host ? 'local' : 'global',
            c: [title, content,
                {_: :span, class: :uri, c: CGI.escapeHTML(ref.to_s.sub /^https?:..(www.)?/, '')}]},
           attrs]} if links
      end

      # paragraph
      def p para
        unless para['uri']
          para['uri'] = '#p_' + Digest::SHA2.hexdigest(rand.to_s)
        end
        para.delete Type # hide typetag, use CSS ::before to denote ¶
        resource para, :p
      end

      def interactions counter
        if type = counter[Schema+'interactionType']
          type = type[0].to_s
          icon = Icons[type] || type
        end
        {_: :span, class: :interactionCount,
         c: [{_: :span, class: :type, c: icon},
             {_: :span, class: :count, c: counter[Schema+'userInteractionCount']}]}
      end

      def keyval kv, skip: []
        return if (kv.keys - skip).empty? # nothing to render

        [{_: :dl,
          c: kv.map{|k, vs|
            {c: [{_: :dt, c: property(Type, [k])}, "\n",
                 {_: :dd, c: property(k, vs)}, "\n"]} unless skip.member? k
          }},
         "\n"]
      end

    end
  end
end
