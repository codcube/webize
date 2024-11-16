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
          uri = Webize::Resource(i['uri'], env) # src

          [{_: :a, href: uri.href, c: uri}, # iframe-src reference

           uri.query_hash.map do |_, v| # URI attrs
             if v.match? HTTPURI
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

        if uri = r['uri']                         # identified node:
          uri = Webize::Resource(uri, env)        # URI
          id = uri.local_id                       # localized fragment identity (representation of transcluded resource in document)

          origin_ref = {_: :a, class: :pointer,   # original pointer
                        href: uri, c: :🔗}

          ref = {_: :a, href: uri.href,           # pointer in current context
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
                'uri', Type, Title, Abstract, Contains,
                XHV + 'namespace',
                Schema + 'height',
                Schema + 'item',
                Schema + 'width',
                Schema + 'version',
                ] # properties we display before delegating
        # we probably should make keyval() accept ordering since that's why we do this
        {_: name,                                # node
         c: [(property Type, r[Type] if r.has_key? Type),
                                                 # type
             ({class: :title,                    # title
               c: r[Title].map{|t| [HTML.markup(t, env), ' ']}}.
                update(ref || {}).               # reference
                update(color ? {style: "background-color: #{color}; color: #000"} : {}) if r.has_key? Title),

             (origin_ref unless inline),         # pointer
                                                 # abstract
             (property Abstract, r[Abstract] if r.has_key? Abstract),
                                                 # item list
             (property Schema + 'item', r[Schema + 'item'] if r.has_key? Schema + 'item'),

             if r[Contains]                      # child nodes
               if TabularChild.member? type.to_s # tabular view
                 property Schema + 'item', r[Contains]
               else                              # inline view
                 r[Contains].map{|c| HTML.markup c, env }
               end
             end,

             keyval(r, inline: inline, skip: skip), # metadata nodes
            ]}.
          update(id ? {id: id} : {}).
          update((id && type == :div) ? {class: :resource, host: uri.host} : {}).
          update(r.has_key?(Schema + 'height') ? {height: r[Schema + 'height'][0]} : {}).
          update(r.has_key?(Schema + 'width') ? {width: r[Schema + 'width'][0]} : {}).
          update((ns = r[XHV + 'namespace']) ? {xmlns: ns[0].class == Hash ? ns[0]['uri'] : ns[0].to_s} : {}).
          update(color ? {style: "background: repeating-linear-gradient(#{45 * rand(8)}deg, #{color}, #{color} 1px, transparent 1px, transparent 16px); border-color: #{color}"} : {})
      end
    end
  end
end
