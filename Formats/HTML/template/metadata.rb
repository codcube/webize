module Webize
  module HTML
    class Node

      # header node
      def head(node) = resource node, :head

      # datatype-specific nodes
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

      def format formats
        formats.map{|f|
                    # 👉 feed(s)
                    # env[:feeds].uniq.map{|feed|
                    #   feed = Resource.new(feed).env env
                    #   [{_: :a, href: feed.href, title: feed.path, c: FeedIcon, id: 'f' + Digest::SHA2.hexdigest(feed.uri)}.
                    #      update((feed.path||'/').match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {}), "\n"]},

          puts f
        }
      end

      # graph provenance listing
      def graph_source(s) = table s,
                                  attrs: ['uri', Creator, Title, Link, To],
                                  heading: false

      def identifier uris
        (uris.class == Array ? uris : [uris]).map{|uri|
          u = Webize::Resource uri, env # URI instance

          [{_: :a, c: :🔗, href: u.href}, # reference
           if u.host                      # remote reference?
             [{_: :a, c: :📦, href: '/' + u.storage.fsPath}, # cache reference
              {_: :a, c: :↗, href: u.uri, class: :origin}] # origin reference
           end]
        }
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
