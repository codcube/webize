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

        [{_: :span,
          class: :image,
          c: [if image.has_key? 'uri'
              {_: :img,
               src: Webize::Resource((env[:base].join image['uri']), env).href,
               alt: (image[Abstract] ||
                     image[Title]).to_s}
              end,

              keyval(image,
                     inline: true,
                     skip: [Type, 'uri'])]},
         ' ']
      end

      def figure(f) = inlineResource f, :figure
      def picture(p) = inlineResource p, :span
      def source(s) = inlineResource s, :span

      def svg(node) = unlabeledResource node, :svg

    end
  end
end
