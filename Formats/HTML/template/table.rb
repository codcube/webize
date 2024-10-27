
module Webize
  module HTML
    class Property

      # table layout: graph <> table, resource <> row, property <> column
      def table graph, attrs: nil, id: nil, skip: []
        graph = graph.select{|g| g.respond_to? :keys} # resources
        return unless graph.size > 0               # empty graph?
        all_attrs = graph.map(&:keys).flatten.uniq # all attributes

        attrs = if attrs # union of requested and available attrs
                  attrs & all_attrs
                else     # all attrs excluding skiplist
                  all_attrs - skip
                end

        {_: :table, class: :tabular, # <table> of resources
         c: [({_: :thead,            # <thead> of properties
               c: {_: :tr, c: attrs.map{|k|
                     p = Webize::URI(k)
                     slug = p.display_name
                     icon = Icons[p.uri] || slug unless k == 'uri'
                     [{_: :th,       # <th> heading of property column
                       c: icon && {  # skip empty <span> if unlabeled
                         _: :span,   # <span> label of property
                         title: k,
                         c: icon,
                       }}, "\n"]}}} if env),
             {_: :tbody,
              c: graph.map{|resource|
                [{_: :tr, c: attrs.map{|k| # <tr> row of resource
                    [{_: :td, property: k, # <td> cell of attribute/property
                      c: if resource.has_key? k
                       Property.new(k).env(env).markup resource[k]
                      end},
                     "\n" ]}}, "\n" ]}}]}.
          update(id ? {id: id} : {})
      end

    end
    class Node

      # display children of these node types in tabular format
      TabularChild = %w(form ol ul select)

      # list elements
      def dd(node) = inlineResource node, :dd
      def dl(node) = blockResource node, :dl
      def dt(node) = inlineResource node, :dt
      def li(node) = resource node, :li
      def ol(node) = resource node, :ol
      def ul(node) = resource node, :ul

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
