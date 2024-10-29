module Webize
  module HTML
    class Property

      Markup[Image] = :img

      def img images
        # all objects of this predicate considered an image.
        # this is a common pattern in JSON where the image URI is in a string value or object without type info alongside it
        # referring-context is more explicit than extension-sniffing heuristics which miss any image without a classic fs-name extension,
        # common with content-addressed / hash-derived CDN URLs, specialized image-servers etc. predicate URI says it's an image so we'll take its word
        images.map do |i|
          Node.new(env[:base]).env(env).img i # image
        end
      end
    end
    class Node

      Markup[Image] = :img

      def img image
        (puts "not an Image", image; return) unless image.class == Hash  # required resource
        (puts "no Image URI", image; return) unless image.has_key? 'uri' # required URI

        i = Webize::Resource env[:base].join(image['uri']), env
        return :🚫 if i.deny?         # blocked URI

        if env[:images].has_key? i     # shown image?
          [{_: :a, c: :🖼️,             # link to existing image
            href: '#' + i.local_id,
            class: :image_reference},
           ' ']
        else
          env[:images][i] = true       # mark as shown
          [{_: :img, id: i.local_id,   # IMG element
            src: i.href,               # SRC attribute
            alt: (image[Abstract] ||   # ALT attribute
                  image[Title])&.join},
           keyval(image, inline: true, # node metadata
                  skip: ['uri', Type]),
           ' ']
        end
      end

      # container for image and associated metadata
      # note: <img> in HTML is mapped to this by default, because:
      # metadata as innerHTML or attrs of img is eaten / not displayed by most user-agents in the wild, and
      # an <img> has a node-id URI distinct from the image URI

      # example: HTML <img id=container src=imgURI> is equivalent to
      #          RDF  <#container> a <xhv:img>
      #               <#container> <dc:Image> <imgURI>

      # we also allow blank nodes, e.g. <img> with no id assigned
      # container node is <span>, since some useragents balk at <div> block element inside <a> which often wraps this
      def imageContainer(c) = {_: :span, class: :image,                          # container
                               c: keyval(c, inline: true, skip: ['uri', Type])}. # image and metadata
                                update(c['uri'] ? {id: Webize::Resource(env[:base].join(c['uri']),env).local_id} : {}) # local identifier

      def figure(f) = inlineResource f, :figure
      def picture(p) = inlineResource p, :span
      def source(s) = inlineResource s, :span

      def svg(node) = unlabeledResource node, :svg

    end
  end
end
