module Webize
  module HTML
    class Node

      # document header
      def head(node) = resource node, :head

      # form elements
      def form(node) = resource node, :form
      def select(node) = resource node, :select

    end
    class Property

      # property-markup methods

      def abstract as
        {class: :abstract,
         c: as.map{|a| [(HTML.markup a, env), ' ']}}
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

      def label labels
        labels.map{|l|
          next unless l.class == RDF::Literal
          {_: :span, class: :label, c: HTML.markup(l, env)}}
      end

      def origin locations
        locations.map{|l|
          {_: :a, href: l.uri, c: :↗, class: :origin, target: :_blank}}
      end

      def rdf_type types, inline: false
        types.map{|t|
          t = Webize::Resource t.class == Hash ? t['uri'] : t, env
          content = if Icons.has_key? t.uri
                      Icons[t.uri]
                    else
                      t.display_name
                    end
          if inline
            content
          else
            {
              #_: :a,
              _: :span,
              class: :type,
              #href: t.href,
              title: t.uri,
              c: content,
            }
          end
        }
      end

      def status_code code
        code.map{|status|
          HTTP::StatusIcon[status.to_i] || status}
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
  end
end
