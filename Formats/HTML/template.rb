
# default templates
require_relative 'template/document.rb' # HTML document
require_relative 'template/metadata.rb' # basic metadata fields
require_relative 'template/resource.rb' # generic resource
require_relative 'template/table.rb'    # tabular layout
require_relative 'template/text.rb'  # DOM nodes

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
