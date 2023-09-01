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

    MarkupPredicate[Video] = -> videos, env {
      videos.map{|v|
        puts :VIDEO, v.class, v if [Hash, String].member? v.class
        Markup[Video][{'uri' => v.to_s}, env]}}

    Markup[Video] = -> video, env {
      v = Webize::Resource env[:base].join(video['uri']), env # video resource

      if v.uri.match? /v.redd.it/
        v += '/DASHPlaylist.mpd' # append playlist suffix
        dashJS = Webize::Resource 'https://cdn.dashjs.org/latest/dash.all.min.js', env
      end

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
                 c: [{_: :img, src: Webize::Resource("https://i.ytimg.com/vi_webp/#{id}/sddefault.webp", env).href},
                     {class: :icon, c: '&#9654;'}]}, {id: player}]
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
