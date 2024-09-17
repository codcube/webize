module Webize
  module HTML
    class Property

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

    end
    class Node

      def resource r, type = :div
                                                 # node name
        name = [:form, :head, :select].
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
                elsif r.has_key?(To) && Identifiable.member?(r[To][0].class)
                  '#' + Digest::SHA2.hexdigest(   # message-destination / group color
                    Webize::URI.new(r[To][0]).display_name)[0..5]
                elsif uri
                  if uri.deny?                    # blocked resource
                    :red
                  elsif HostColor.has_key? uri.host
                    HostColor[uri.host]           # host color
                  end
                end

        shown = ['#color', '#style', '#new',
                 'uri',
                 Title, Contains]  # properties we handle before delegating to generic keyval render

        [{_: name,                                # node
          c: [({class: :title,                    # title
                c: r[Title].map{|t|
                  HTML.markup t, env}}.           # attach link to title if exists
                 update(ref || {}) if r.has_key? Title),
              "\n", keyval(r, skip: shown),       # keyval render remaining fields
              if r[Contains]                      # child nodes
                if TabularChild.member? type.to_s # tabular view of child nodes
                  property Schema + 'item', r[Contains]
                else
                  r[Contains].map{|c|             # generic inlining of child nodes
                    HTML.markup c, env}
                end
              end,
              origin_ref,                         # origin pointer
             ]}.
           update(id ? {id: id} : {}).
           update((id && type == :div) ? {class: :resource} : {}).
           update(r.has_key?('#style') ? {style: r['#style'][0]} : {}).
           update(color ? {style: "background: repeating-linear-gradient(#{45 * rand(8)}deg, #{color}, #{color} 1px, transparent 1px, transparent 16px); border-color: #{color}"} : {}), "\n"]
      end
    end
  end
end
