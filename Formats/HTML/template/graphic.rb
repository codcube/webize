module Webize
  module HTML
    class Property

      Markup[Image] = :img

      def img images
        # all objects of this predicate considered an image - predicate URI says it's an image so we'll take its word

        # supports a common pattern in JSON where the image URI is in a string-value or object without type info alongside it
        # referring-context is more explicit than extension-sniffing heuristics which miss any image without a classic fs-name extension,
        # common with content-addressed / hash-derived CDN URLs, specialized image-servers etc
        images.map do |i|
          Node.new(env[:base]).env(env).img i # image
        end
      end
    end
    class Node

      Markup[Image] = :img

      def img image
        (#puts "not an Image", image
         return) unless image.class == Hash  # required resource
        (#puts "no Image URI", image
         return) unless image.has_key? 'uri' # required URI

        i = Webize::Resource env[:base].join(image['uri']), env
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
      # note <img> has a URI distinct from its image URI, as in this example:
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

    end
  end
end
