module Webize
  module HTML
    class Property

      Markup[Image] = :img

      def img images
        # all objects of this predicate considered an image.
        # this is a common pattern in JSON where the image URI is in a string value or object without type info alongside it. referring-context is more explicit than extension-sniffing heuristics which miss any image without a classic fs-name extension - quite common now with content-addressing / hash-based CDN URLs, specialized image-servers etc. the predicate URI says it's an image so we'll take its word and bypass the object type dispatcher
        images.map do |i|
          Node.new(env[:base]).env(env).img i
        end
      end
    end
    class Node

      Markup[Image] = :img

      def img image, container: false
        # container: indirect @src reference in RDF: <#container> <dc:Image> <imageURI>
        # no-container: direct @src reference at resource URI
        return unless image.class == Hash

        # optional node identifier (blank-node containers allowed)
        i = Webize::Resource env[:base].join(image['uri']), env if image.has_key? 'uri'

        [{_: :span, class: :image, # container for <img> and metadata fields
          c: [
            unless container
              if !i || i.deny? # placeholder if blocked or empty locator
                {_: :span, c: :🖼️, title: i}
              else
                {_: :img,                 # <img> element
                 src: i.href,             # src attribute
                 alt: (image[Abstract] || # alt attribute
                       image[Title])&.join}
              end
            end,

              keyval(image,    # metadata and contained images
                     inline: true,
                     skip: [Type, 'uri'])]}.
           update(i ? {id: i.local_id} : {}), # container URI
         ' ']
      end

      # <img>
      def imageContainer(i) = img i, container: true

      def figure(f) = inlineResource f, :figure
      def picture(p) = inlineResource p, :span
      def source(s) = inlineResource s, :span

      def svg(node) = unlabeledResource node, :svg

    end
  end
end
