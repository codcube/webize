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

      def cache locations
        locations.map{|l|
          {_: :a, href: '/' + l.fsPath, c: :📦}}
      end

      def creator creators
        creators.map{|creator|
          [ # colorize by URI
            if Identifiable.member? creator.class
              uri = Webize::Resource.new(creator).env env
              name = uri.display_name
              color = Digest::SHA2.hexdigest(name)[0..5]
              {_: :a, class: :from, href: uri.href, style: "background-color: ##{color}", c: name}
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

      # LS - table of resource URIs and filesystem metadata
      def local_source(nodes) = table nodes,
                                      attrs: [Type, 'uri', Title, '#childDir', '#entry', Size, Date],
                                      id: :local_source

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
          end}
      end

      def cache_info(nodes) = nodes.map do |node|
        next unless node.class == Hash
        next unless uri = node['uri']

        uri = Webize::Resource uri, env

        node.update({HT+'host' => [uri.host],        # host
                     HT+'path' => [uri.path],        # path
                     '#cache' => [POSIX::Node(uri)], # 👉 cache
                     '#origin' => [uri]})            # 👉 upstream/origin resource
      end

      def content_type(types) = types.map do |type|
        MIME.format_icon type.to_s
      end

      # generic graph listing - cache+origin pointers and summary fields
      def graph_source(nodes) = table cache_info(nodes), attrs: [LDP + 'prev', 'uri',
                                                                 Title, '#origin',
                                                                 HT + 'host', HT + 'path',
                                                                 Image, Creator, Date,
                                                                 '#cache', LDP + 'next']

      # render resource URIs, remote/origin response metadata, and local cache-pointers and transaction timings
      def remote_source(nodes) = table cache_info(nodes),
                                       id: :remote_source,
                                       attrs: [HT+'status',
                                               'uri', HT + 'host', HT + 'path',
                                               '#cache', '#origin',
                                               Title,
                                               HT + 'Content-Type', HT + 'Content-Length', HT + 'Server', HT + 'X-Powered-By',
                                               '#fTime', '#pTime']

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
            if Identifiable.member? r.class
              uri = Webize::Resource.new(r).env env
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
