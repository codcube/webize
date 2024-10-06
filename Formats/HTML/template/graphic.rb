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

        [{class: :image,
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

      def svg node
        node.delete Label
        inlineResource node, :svg
      end

    end
  end
end
