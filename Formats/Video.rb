module Webize
  module MOV
    class Format < RDF::Format
      content_type 'video/quicktime', :extensions => [:mov,:MOV]
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = RDF::URI(options[:base_uri] || '#mp3')
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
      end
    end
  end
  module MP4
    class Format < RDF::Format
      content_type 'video/mp4', :extension => :mp4
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = RDF::URI(options[:base_uri] || '#mp4')
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
      end
    end
  end
  module WebM
    class Format < RDF::Format
      content_type 'video/webm', :extension => :webm
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = RDF::URI(options[:base_uri] || '#webm')
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
      end
    end
  end
  module HTML

    MarkupPredicate[Video] = -> videos, env {
      videos.map{|v|
        Markup[Video][ v.class == Hash ? v : {'uri' => v.to_s}, env ]}}

    Markup[Video] = -> video, env {
      v = Webize::Resource env[:base].join(video['uri']), env # video URI
      video.delete Video

      {class: :video,
       c: [{_: :span, style: 'font-size: 4.2em', c: :🎞},
           (MarkupPredicate[Title][video.delete(Title), env] if video.has_key? Title),
           HTML.keyval(video, env), '<br>',
           if v.uri.match? /youtu/ # YouTube

             id = v.query_hash['v'] || v.parts[-1]
             player = 'yt' + Digest::SHA2.hexdigest(rand.to_s)

             [ # thumbnail node
               {_: :a, id: 'preembed' + Digest::SHA2.hexdigest(rand.to_s),
               class: :preembed,
               href: player,
               onclick: "inlineplayer(\"##{player}\",\"#{id}\"); this.remove()",
               c: [{_: :img,
                    src: Webize::Resource("https://i.ytimg.com/vi_webp/#{id}/sddefault.webp", env).href},
                   {class: :icon, c: '&#9654;'}]},

               # player node
              {id: player}]
          else                     # video tag
            [{_: :video, src: v.uri, controls: :true}, '<br>',
             {_: :a, href: v.uri, c: v.display_name}]
           end]}}

  end
end
