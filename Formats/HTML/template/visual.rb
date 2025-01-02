module Webize
  module HTML
    class Property

      Markup[Image] = :img
      Markup[Video] = :video

      def img images
        # all objects of this predicate considered an image - predicate URI says it's an image so we'll take its word
        # supports a common pattern in JSON where the image URI is in a string-value or object without type info alongside it
        # referring-context is more explicit than extension-sniffing heuristics which miss any image without a classic fs-name extension,
        # common with content-addressed / hash-derived CDN URLs, specialized image-servers etc
        images.map do |i|
          Node.new(env[:base]).env(env).img i # image
        end
      end

      def video videos
        videos.map{|v|
          Node.new(env[:base]).env(env).videotag v}
      end

    end
    class Node

      Markup[Image] = :img
      Markup[Video] = :videotag

      def img image
        (puts ["not an image resource", image.class, image].join " "
         return) unless image.class == Hash  # required resource

        # URI becomes image @src in this method. if you've a description of an <img> tag,
        # or @src is in an image predicate, use #imageContainer below
        return unless image.has_key? 'uri' # required URI

        i = Webize::Resource env[:base].join(image['uri']), env # image resource

        return {_: :span, href: i.uri, c: :🚫} if i.deny? # blocked image

        if env[:images].has_key? i     # shown image?
          [{_: :a, c: :🖼️,             # link to existing image
            href: ['#', i.local_id].join,
            class: :image_reference},
           ' ']
        else
          env[:images][i] = true     # mark as shown
          [{_: :img, id: i.local_id, # IMG element
            src: if Remote_Cache     # SRC attribute
             Remote_Cache + i.uri    # peer cache
           elsif Local_Cache
             i.href                  # local cache
           else
             i.uri                   # origin location
            end,
            alt: (image[Abstract] || # ALT attribute
                  image[Title])&.join},
           keyval(image,             # node metadata
                  inline: true,
                  skip: ['uri', Type]),
           ' ']
        end
      end

      # container for <img> and associated metadata
      # we introducer a container element. <img> is one already, but
      # metadata as inner nodes or attrs of <img> is not displayed by most user-agents in the wild
      # note <img> has a URI distinct from its image URI, as in:
      # HTML <img id=container src=imgURI>
      # RDF  <#container> a <xhv:img>
      #      <#container> <dc:Image> <imgURI>
      def imageContainer(c) = {_: :span, class: :image,                          # container
                               c: keyval(c, inline: true, skip: ['uri', Type])}. # image and metadata
                                update(c['uri'] ? {id: Webize::Resource(env[:base].join(c['uri']),env).local_id} : {}) # local identifier

      def figure(f) = inlineResource f, :figure
      def picture(p) = inlineResource p, :span
      def source(s) = inlineResource s, :span

      def svg(node) = inlineResource node, :svg

      def videotag video
        (puts "not a video", video
         return) unless video.class == Hash                    # required resource
        (puts "no video URI", video
         return) unless video.has_key? 'uri'                   # required URI

        v = Webize::Resource env[:base].join(video['uri']),env # video resource

        return if env[:videos].has_key? v                      # shown video
        env[:videos][v] = true                                 # mark as shown

        {class: 'video resource',
         c: [({class: :title,                                  # title
               c: video.delete(Title).map{|t|
                 HTML.markup t, env}} if video.has_key? Title),

             if v.host == YT_host                              # Youtube video
               #return videotag({'uri' => v.relocate.uri}) if v.relocate?
               id = v.query_hash['v']                          # video id
               player = 'yt'+Digest::SHA2.hexdigest(rand.to_s) # player id
               video.delete Image                              # strip thumbnail definitions
               [{_: :a, id: 'preembed' + Digest::SHA2.hexdigest(rand.to_s), # pre-embed thumbnail
                  class: :preembed,                            # on activation:
                  href: '#' + player,                          # focus player (embed)
                  onclick: "inlineplayer(\"##{player}\",\"#{id}\"); this.remove()", # load player
                  c: [{_: :img, src: Webize::Resource("https://i.ytimg.com/vi_webp/#{id}/sddefault.webp", env).href},
                      {class: :icon, c: '&#9654;'}]},          # ▶ icon
                 {id: player}]                                 # player
             else                                              # video
               source = {_: :source, src: v.uri}
               source[:type] = 'application/x-mpegURL' if v.extname == '.m3u8'

               [{_: :video, controls: :true,
                 c: source}, '<br>',
                {_: :a, href: v.uri, c: v.display_name}]
             end,
             (keyval video)]}                                  # video attributes
      end
    end
  end
end
