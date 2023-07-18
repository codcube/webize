module Webize
  module MOV
    class Format < RDF::Format
      content_type 'video/quicktime', :extensions => [:mov,:MOV]
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#mp3').R
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
        @subject = (options[:base_uri] || '#mp3').R 
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
        @subject = (options[:base_uri] || '#mp3').R 
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

    MarkupPredicate[Video] = -> videos, env {videos.map{|v| Markup[Video][v, env]}}

    Markup[Video] = Markup['WEB_PAGE_TYPE_WATCH'] = -> video, env {

      if video.class == Hash
        resource = video.dup
        ['http://www.youtube.com/xml/schemas/2015#channelId',
         'http://www.youtube.com/xml/schemas/2015#videoId',
         Video].map{|p|
          resource.delete p}
        video = video['https://schema.org/url'] || video[Schema+'contentURL'] || video[Schema+'url'] || video[Link] || video['uri']
        (Console.logger.warn 'no video URI!'; video = '#video') unless video
      end

      if video.class == Array
        Console.logger.warn ['multiple videos: ', video].join if video.size > 1
        video = video[0]
        (Console.logger.warn 'empty video resource'; video = '#video') unless video
      end

      if video.to_s.match? /v.redd.it/ # reddit?
        video += '/DASHPlaylist.mpd'   # append playlist suffix to URI
        dashJS = 'https://cdn.dashjs.org/latest/dash.all.min.js'.R env
      end

      v = env[:base].join(video).R env # video resource
      {class: :video,                  # video markup
       c: [if v.uri.match? /youtu/     # youtube?
           env[:tubes] ||= {}          # dedupe videos
           q = v.query_values || {}
           id = q['v'] || v.parts[-1]
           t = q['start'] || q['t']
           unless env[:tubes].has_key?(id)
             env[:tubes][id] = id
             if id == env[:qs]['v']    # 'navigated to' video loaded by default
               [{_: :a, id: :mainVideo},
                {_: :iframe, class: :main_player, width: 640, height: 480, src: "https://www.youtube.com/embed/#{id}#{t ? '?start='+t : nil}",
                 frameborder: 0, allow: 'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture', allowfullscreen: :true}]
             else                      # other videos, tap to load
               player = 'embed' + Digest::SHA2.hexdigest(rand.to_s)
               [{class: :preembed, onclick: "inlineplayer(\"##{player}\",\"#{id}\"); this.remove()",
                 c: [{_: :img, src: "https://i.ytimg.com/vi_webp/#{id}/sddefault.webp".R(env).href},{class: :icon, c: '&#9654;'}]}, {id: player}]
             end
           end
          else                         # generic video markup
            [dashJS ? "<script src='#{dashJS.href}'></script>" : nil,
             {_: :video, src: v.uri, controls: :true}.update(dashJS ? {'data-dashjs-player' => 1} : {}), '<br>',
             {_: :a, href: v.uri, c: v.display_name}]
           end,
           (Markup[BasicResource][resource, env] if resource)]}}

  end
end
