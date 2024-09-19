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
    class Property

      Markup[Video] = :video

      def video videos
        videos.map{|v|
          Node.new(env[:base]).env(env).videotag v}
      end
    end
    class Node

      Markup[Video] = :videotag

      def videotag video
        unless video.class == Hash
          video = {'uri' => video.to_s}
          puts "not a video resource: #{video.class} #{video}"
        end

        v = Webize::Resource env[:base].join(video['uri']), env                    # video resource

        {class: 'video resource',
         c: [({class: :title,                                                      # title
               c: video.delete(Title).map{|t|
                 HTML.markup t, env}} if video.has_key? Title),

             if v.uri.match? /youtu/                                               # Youtube
               id = v.query_hash['v'] || v.parts[-1]                                # video id
               player = 'yt' + Digest::SHA2.hexdigest(rand.to_s)                    # player id
               video.delete Image                                                   # strip duplicate thumbnail(s)
               [{_: :a, id: 'preembed' + Digest::SHA2.hexdigest(rand.to_s),         # pre-embed thumbnail
                  class: :preembed,                                                 # on activation:
                  href: '#' + player,                                               # focus player (embed)
                  onclick: "inlineplayer(\"##{player}\",\"#{id}\"); this.remove()", # load player
                  c: [{_: :img, src: Webize::Resource("https://i.ytimg.com/vi_webp/#{id}/sddefault.webp", env).href},
                      {class: :icon, c: '&#9654;'}]},                               # ▶ icon
                 {id: player}]                                                      # player
             else                                                                  # generic video
               source = {_: :source, src: v.uri}
               source[:type] = 'application/x-mpegURL' if v.extname == '.m3u8'

               [{_: :video, controls: :true,
                 c: source}, '<br>',
                {_: :a, href: v.uri, c: v.display_name}]
             end,
             (keyval video)]}                                                      # extra attributes
      end
    end
  end
end
