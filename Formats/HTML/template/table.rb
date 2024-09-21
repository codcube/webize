module Webize
  module HTML
    class Property

      # graph index
      def graph_index nodes, details: false
        nodes.map do |node|
          next unless uri = node['uri']
          uri = Webize::Resource uri, env

          # pointers to upstream and cached resources
          node.update({'#cache' => [POSIX::Node(uri)],
                       '#origin' => [uri]})

          # detailed info
          node.update({'#host' => [uri.host],
                       '#path' => [uri.path]}) if details
        end

        index_table nodes
      end

      def graph_index_detailed nodes
        graph_index nodes, details: true
      end

      # table without inlining of child/contained nodes - useful for nodes where child-node points to parent, leading to large, even infinite(!) tables
      def index_table(nodes) = table nodes, skip: [Abstract, Contains, Content]

      def table graph, skip: []
        graph = graph.select{|g| g.respond_to? :keys}
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
                 c: {_: :tr, c: keys.map{|k| # table heading
                       p = Webize::URI(k)
                       slug = p.display_name
                       icon = Icons[p.uri] || slug unless k == 'uri'
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

    end
    class Node

      # display children of these node types in tabular format
      TabularChild = %w(form head ol ul select)

      # list elements
      def ul(node) = resource node, :ul
      def ol(node) = resource node, :ol
      def li(node) = resource node, :li

      # table elements
      def table(node) = bareResource node, :table
      def thead(node) = bareResource node, :thead
      def tbody(node) = bareResource node, :tbody
      def tfoot(node) = bareResource node, :tfoot
      def th(node) = bareResource node, :th
      def tr(node) = bareResource node, :tr
      def td(node) = bareResource node, :td

    end
  end
end
