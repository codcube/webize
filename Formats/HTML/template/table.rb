
module Webize
  module HTML
    class Property

      # graph index
      def graph_index nodes, details: false
        nodes.map do |node|
          (puts 'not a node?', node; next) unless node.class == Hash
          next unless uri = node['uri']

          uri = Webize::Resource uri, env

          # detailed info
          node.update({'#host' => [uri.host],
                       '#path' => [uri.path]}) if details

          # pointers to upstream and cached graph
          node.update({'#cache' => [POSIX::Node(uri)],
                       '#origin' => [uri]})

        end

        index_table nodes
      end

      def graph_index_detailed nodes
        graph_index nodes, details: true
      end
      # eliminate most inlining to output a basic tabular list of resources i.e. don't include "main content" and containment pointers
      def index_table(nodes) = table nodes, skip: [Abstract, Contains, Content, SIOC + 'has_container', SIOC + 'reply_of']

      # table layout: graph <> table, resource <> row, property <> column
      def table graph, attrs: nil, skip: []
        graph = graph.select{|g| g.respond_to? :keys} # resources
        return unless graph.size > 0               # empty graph?

        attrs ||= graph.map(&:keys).flatten.uniq -
                  skip               # attr skiplist

        {_: :table, class: :tabular, # <table> of resources
         c: [({_: :thead,            # <thead> of properties
               c: {_: :tr, c: attrs.map{|k|
                     p = Webize::URI(k)
                     slug = p.display_name
                     icon = Icons[p.uri] || slug unless k == 'uri'
                     [{_: :th,       # property heading
                       c: icon && {  # skip empty <span> if unlabeled
                         _: :span,   # <span> property label
                         title: k
                         c: icon,
                       }}, "\n"]}}} if env),
             {_: :tbody,
              c: graph.map{|resource|
                [{_: :tr, c: attrs.map{|k| # <tr> resource -> row
                    [{_: :td, property: k, # cell in property column
                      c: if resource.has_key? k
                       Property.new(k).env(env).markup resource[k]
                      end},
                     "\n" ]}}, "\n" ]}}]}
      end

    end
    class Node

      # display children of these node types in tabular format
      TabularChild = %w(form ol ul select)

      # list elements
      def ul(node) = resource node, :ul
      def ol(node) = resource node, :ol
      def li(node) = resource node, :li

      # table elements
      def table(node) = blockResource node, :table
      def thead(node) = blockResource node, :thead
      def tbody(node) = blockResource node, :tbody
      def tfoot(node) = blockResource node, :tfoot
      def th(node) = blockResource node, :th
      def tr(node) = blockResource node, :tr
      def td(node) = blockResource node, :td

      # table layout: resource <> table, property <> row
      def keyval kv, inline: false, skip: []
        return if (kv.keys - skip).empty? # nothing to render

        list, key, val = inline ? %w(span span span) : %w(dl dt dd) # element types

        {_: list, class: :kv,
         c: kv.map{|k, vs|
           next if skip.member? k

           [{_: key,
             class: :key,
             c: Property.new(Type).env(env).
               rdf_type([k], inline: inline)},

            {_: val,
             class: :val,
             c: property(k, vs.class == Array ? vs : [vs])},

            inline ? nil : "\n"]}}
      end

    end
  end
end
