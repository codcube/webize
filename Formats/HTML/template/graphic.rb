module Webize
  module HTML
    class Property

      Markup[Image] = :img

      def img images
        images.map do |i|
          Node.new(env[:base]).env(env).img i
        end
      end

    end
    class Node

      Markup[Image] = :img

      def img image
        return puts "not an image resource: #{image.class} #{image}" unless image.class == Hash

        i = Webize::Resource env[:base].join(image['uri']), env if image.has_key? 'uri' # identity

        [{_: :span, class: :image, # wrapping node for image and metadata nodes
          c: [if i
              if i.deny?
                {_: :span, class: :blocked_image, c: :🖼️}
              elsif i.imgURI?
                {_: :img,
                 src: i.href,
                 alt: (image[Abstract] ||
                       image[Title])&.join}
              end
              end,

              keyval(image,
                     inline: true,
                     skip: [Type, 'uri'])]}.
           update(i ? {id: i.local_id} : {}),
         ' ']
      end

      def figure(f) = inlineResource f, :figure
      def picture(p) = inlineResource p, :span
      def source(s) = inlineResource s, :span

      def svg(node) = unlabeledResource node, :svg

    end
  end
end
