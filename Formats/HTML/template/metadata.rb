module Webize
  module HTML
    class Node

      # document header
      def head(node) = resource node, :head

      # form elements
      def form(node) = resource node, :form
      def select(node) = resource node, :select

      # data elements
      def time(node) = inlineResource node, :time

    end
    class Property

      # property-markup methods

      def abstract as
        {class: :abstract,
         c: as.map{|a| [(HTML.markup a, env), ' ']}}
      end

      def creator creators
        creators.map{|creator|
          [ # colorize by URI
            if creator.class == Hash && creator['uri']
              author = Webize::Resource env[:base].join(creator['uri']), env # author URI
              name = author.display_name
              color = Digest::SHA2.hexdigest(name)[0..5]
              {_: :a, class: :from, href: author.href, style: "background-color: ##{color}", c: name}
            else
              HTML.markup creator, env
            end,
            ' ']}
      end

      def identifier uris
        (uris.class == Array ? uris : [uris]).map{|uri|
          {_: :a, c: :🔗,
           href: env ? Webize::Resource(uri, env).href : uri,
           id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}
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
          end}
      end

      def content_type(types) = types.map do |type|
        MIME.format_icon type.to_s
      end

      def status_code code
        code.map{|status|
          HTTP::StatusIcon[status.to_i] || status}
      end

      def title titles
        titles.map{|t|
          [{_: :span, c: HTML.markup(t, env)},
           {_: :hr}]}
      end

      def to recipients
        recipients.map{|r|
          [# colorize by URI
            if r.class == Hash && r['uri']
              uri = Webize::Resource env[:base].join(r['uri']), env # recipient URI
              name = uri.display_name
              color = Digest::SHA2.hexdigest(name)[0..5]
              {_: :a, class: :to, href: uri.href, style: "background-color: ##{color}", c: ['&rarr;', name].join}
            else
              HTML.markup r, env
            end,
            ' ']}
      end
    end
  end
end
