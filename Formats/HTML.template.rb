require_relative 'HTML.template.document.rb' # document template
require_relative 'HTML.template.domnode.rb'  # document-nodes templates
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

      def identifier uris
        (uris.class == Array ? uris : [uris]).map{|uri|
          {_: :a, c: :🔗,
           href: env ? Webize::Resource(uri, env).href : uri,
           id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}
      end

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

      # absolute barebones generic resource markup. the full resource renderer wraps this and adds some links, specially-handles Title and so on
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
