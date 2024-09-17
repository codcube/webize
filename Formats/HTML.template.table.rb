module Webize
  module HTML
    class Property

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

      # table of nodes without inlining contained/child nodes - useful for directories etc where child-node data is loaded and points back to parent, leading to large, even infinite(!) tables. one way to stop recursion before it hits the toplevel loop-detector in #markup
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

    end
  end
end
