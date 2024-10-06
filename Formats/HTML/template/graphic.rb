module Webize
  module HTML
    class Property

      Markup[Image] = :img

      def img images
        images.map{|i|
          Node.new(env[:base]).env(env).img i}
      end

    end
    class Node

      Markup[Image] = :img

      def img image
        unless image.class == Hash
          puts "not an image resource: #{image.class} #{image}"
          image = {'uri' => image.to_s}
        end

        src = Webize::Resource((env[:base].join image['uri']), env).href

        [{class: :image,
          c: [{_: :a, href: src,
               c: {_: :img, src: src}},

              if image.has_key? Abstract
                ['<br>',
                 {class: :caption,
                  c: image[Abstract].map{|a|
                    [(HTML.markup a,env), ' ']}}]
              end,

              keyval(image, skip: [Abstract, Type, 'uri'])]},
         ' ']
      end

      def svg node
        node.delete Label
        inlineResource node, :svg
      end

    end
  end
end
