module Webize
  module HTML
    class Property

      def buttons resources
        [{_: :style, c: "a.button {background-color: ##{Digest::SHA2.hexdigest(uri)[0..5]}; color: white}"},

         resources.sort_by{|r| r['uri'] }.map{|r|
           uri = Webize::Resource r['uri'], env

           [{_: :a,
             href: uri.href,
             id: 'b' + Digest::SHA2.hexdigest(rand.to_s),
             class: :button,
             c: uri.display_name},
            "\n"]}]
      end

      def iframe iframes
        # TODO click-to-inline original iframe?
        iframes.map do |i|
          (puts [:iframe, i].join ' '; next) unless i.class == Hash
          uri = Webize::Resource(i['uri'], env) # src

          [HTML.markup(uri, env), # src reference

           uri.query_hash.map do |_, v| # URI attrs
             if v&.match? HTTPURI
               {_: :a, href: v, c: v}
             end
           end]
        end
      end

    end
    class Node

      def div(node) = blockResource node, :div

      def docfrag(f) = if f.has_key? 'uri'
                         div f # fragment <div> with identifier
                       else    # inlined un-named fragment
                         f[Contains]&.map{|frag|
                           HTML.markup frag, env}
                       end

      def blockResource re, type
        re.delete Type # strip RDF typetag denoted with CSS ::before
        [(resource re, type), "\n"]
      end

      def inlineResource re, type
        re.delete Type
        resource re, type, inline: true # metadata with SPAN instead of DL/DT/DD
      end

      # mint an identifier if nonexistent TODO check dc:identifier field as well as default 'uri'
      def identifiedResource re, type
        re['uri'] ||= ['#', type,'_',
                       Digest::SHA2.hexdigest(rand.to_s)].join
        blockResource re, type
      end

      def resource r, type = :div, inline: true
        name = [:form, :head, :select].           # node name
                 member?(type) ? :div : type

        if uri = r['uri']                         # identified?
          uri = Webize::Resource(uri, env)        # URI
          id = uri.local_id                       # local identifier for resource representation
          ref = {_: :a, href: uri.href,           # resource reference
                 id: 'p'+Digest::SHA2.hexdigest(rand.to_s)}
        end

        color = if r.has_key? '#color'            # specified color
                  r['#color'][0]
                elsif r.has_key? '#new'           # new/updated resource highlight
                  '#8aa'
                elsif uri
                  if uri.deny?                    # blocked resource
                    :red
                  elsif HostColor.has_key? uri.host
                    HostColor[uri.host]           # host color
                  end
                end

        skip = ['#color', '#new',
                Type, Title, Contains,
                XHV + 'colspan',
                XHV + 'rowspan',
                XHV + 'namespace',
                XHV + 'height',
                XHV + 'width',
                ] # properties we use before delegating to #keyval

        # node
        node = {_: name,                                # node type
                c: [(property Type, r[Type] if r.has_key? Type),

                    # title
                    ({class: :title,
                      c: r[Title].map{|t| [HTML.markup(t, env), ' ']}}.
                       update(ref || {}).               # reference
                       update(color ? {style: "background-color: #{color}; color: #000"} : {}) if r.has_key? Title),

                    # child nodes
                    if r[Contains]
                      if TabularChild.member? type.to_s # tabular view
                        property Schema + 'item', r[Contains]
                      else                              # inline view
                        r[Contains].map{|c| HTML.markup c, env }
                      end
                    end,

                    # node metadata
                    keyval(r, inline: inline, skip: skip),
                   ]}

        # node identity
        if id
          node[:id] = id
          if type == :div
            # generic identified-node styling
            node[:class] = :resource
            node[:host] = uri.host
          end
        end

        # node attributes
        %w(colspan height namespace rowspan width).map{|attr|
          a = XHV + attr
          if r.has_key? a
            node[attr] = if r[a][0].class == Hash
                           r[a][0]['uri']
                         else
                           r[a][0].to_s
                         end
          end}

        if color
          node[:style] = "background: repeating-linear-gradient(#{45 * rand(8)}deg, #{color}, #{color} 1px, transparent 1px, transparent 16px); border-color: #{color}"
        end

        node
      end
    end
  end
end
