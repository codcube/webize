module Webize

  module AAC
    class Format < RDF::Format
      content_type 'audio/aac', :extension => :aac
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @options = options
        @subject = RDF::URI(options[:base_uri] || '#aac')
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

  module MP3
    class Format < RDF::Format
      content_type 'audio/mpeg', :extension => :mp3
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @options = options
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

  module Opus
    class Format < RDF::Format
      content_type 'audio/ogg', extensions: [:ogg, :opus],
                   aliases: %w(audio/opus;q=0.8
                          application/ogg;q=0.8)
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @options = options
        @subject = RDF::URI(options[:base_uri] || '#opus')
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

  module M4S
    class Format < RDF::Format
      content_type 'audio/m4a', extensions: [:m4a, :m4s],
                   aliases: %w(
                    audio/x-m4a;q=0.8
                    audio/x-wav;q=0.8
                    audio/m4s;q=0.8)
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @options = options
        @subject = RDF::URI(options[:base_uri] || '#m4s')
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

  module Wav
    class Format < RDF::Format
      content_type 'audio/wav', :extension => :wav
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @options = options
        @subject = RDF::URI(options[:base_uri] || '#wav')
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

  module Playlist
    class Format < RDF::Format
      content_type 'application/vnd.apple.mpegurl', :extension => :m3u8
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @options = options
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = RDF::URI(options[:base_uri] || '#js')
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
        playlist_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, RDF::URI(p), o,
                                     :graph_name => @subject)}
      end

      def playlist_triples
      end
    end
  end

  module MIME
    # audio-file triples via taglib
    def audio_triples graph
      require 'taglib'

      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Audio))
      graph << RDF::Statement.new(self, RDF::URI(Title), Rack::Utils.unescape_path(basename))
      TagLib::FileRef.open(fsPath) do |fileref|
        unless fileref.null?
          tag = fileref.tag
          graph << RDF::Statement.new(self, RDF::URI(Title), tag.title)
          graph << RDF::Statement.new(self, RDF::URI(Creator), tag.artist)
          graph << RDF::Statement.new(self, RDF::URI(Date), tag.year) unless !tag.year || tag.year == 0
          graph << RDF::Statement.new(self, RDF::URI(Contains), tag.comment)
          graph << RDF::Statement.new(self, RDF::URI(Schema+'album'), tag.album)
          graph << RDF::Statement.new(self, RDF::URI(Schema+'track'), tag.track)
          graph << RDF::Statement.new(self, RDF::URI(Schema+'genre'), tag.genre)
          graph << RDF::Statement.new(self, RDF::URI(Schema+'length'), fileref.audio_properties.length_in_seconds)
        end
      end
    end
  end

  module HTML
    class Property

      Markup[Audio] = :audio

      def audio as
        as.map{|a|
          Node.new(env[:base]).env(env).audiotag a}
      end
    end
    class Node

      Markup[Audio] = :audiotag

      def audiotag audio
        return puts "not an audio resource: #{audio.class} #{audio}" unless audio.class == Hash

        # resolve locator to environment context
        src = Webize::Resource((env[:base].join audio['uri']), env)

        {class: 'audio resource',
         c: [{_: :audio,      # audio tag
              src: src.href,
              controls: :true},

             {_: :a,          # audio link
              class: :global,
              href: src.uri,
              c: [:🔊, src.display_name]},

             (keyval audio)]} # extra attributes
      end
    end
  end
end
