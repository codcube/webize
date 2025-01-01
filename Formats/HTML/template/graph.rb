module Webize
  module HTML
    class Property
      
      def cache(locations) = locations.map{|l|
        {_: :a,
         href: '/' + l.fsPath,
         c: :📦}}

      def cache_info(nodes) = nodes.map do |node|
        next unless node.class == Hash
        next unless uri = node['uri']

        uri = Webize::Resource uri, env

        node.update({HT+'host' => [uri.host],        # host
                     HT+'path' => [uri.path],        # path
                     '#cache' => [POSIX::Node(uri)], # 👉 cache
                     '#origin' => [uri]})            # 👉 upstream/origin resource
      end

      # generic graph listing - cache+origin pointers and summary fields
      def graph_source(nodes) = table cache_info(nodes), attrs: [LDP + 'prev', 'uri',
                                                                 Title, '#origin',
                                                                 HT + 'host', HT + 'path',
                                                                 Image, Creator, Date,
                                                                 '#cache', LDP + 'next']

      # POSIX#ls - table of resource URIs and filesystem metadata
      def local_source(nodes) = table nodes,
                                      attrs: [Type, 'uri', Title, '#childDir', '#entry', Size, Date],
                                      id: :local_source

      def origin(locations) = locations.map{|l|
        {_: :a,
         href: l.uri,
         c: :↗,
         class: :origin,
         target: :_blank}}

      # render resource URIs, remote/origin response metadata, and local cache-pointers and transaction timings
      def remote_source(nodes) = table cache_info(nodes),
                                       id: :remote_source,
                                       attrs: [HT+'status',
                                               'uri', HT + 'host', HT + 'path',
                                               '#cache', '#origin',
                                               Title,
                                               HT + 'Content-Type', HT + 'Content-Length', HT + 'Server', HT + 'X-Powered-By',
                                               '#fTime', '#pTime', Date],
                                       heading: false

    end
  end
end
