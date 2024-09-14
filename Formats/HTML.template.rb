
# default templates
require_relative 'HTML.template.document.rb' # HTML document
require_relative 'HTML.template.domnode.rb'  # DOM nodes
require_relative 'HTML.template.metadata.rb' # basic metadata fields
require_relative 'HTML.template.resource.rb' # generic resource
require_relative 'HTML.template.table.rb'    # tabular layout

module Webize
  module HTML
    class Node

      # absolute barebones generic-resource template. the full resource renderer wraps this and adds self-referential link(s)/identifier and title heading
      def keyval kv, skip: []
        return if (kv.keys - skip).empty? # nothing to render

        [{_: :dl,
          c: kv.map{|k, vs|
            [{_: :dt, c: property(Type, [k])}, "\n",
             {_: :dd, c: property(k, vs)}, "\n"] unless skip.member? k
          }},
         "\n"]
      end

    end
  end
end
