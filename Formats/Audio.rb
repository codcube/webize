module Webize

  module AAC
    class Format < RDF::Format
      content_type 'audio/aac', :extension => :aac
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#aac').R
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
      include Console
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
        @subject = (options[:base_uri] || '#opus').R
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
        @subject = (options[:base_uri] || '#m4s').R
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
        @subject = (options[:base_uri] || '#wav').R
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
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = (options[:base_uri] || '#js').R
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
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == Webize::URI || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def playlist_triples
      end
    end
  end

  module POSIX
    # audio-file triples via taglib
    def audio_triples graph
      require 'taglib'

      graph << RDF::Statement.new(self, Type.R, Audio.R)
      graph << RDF::Statement.new(self, Title.R, Rack::Utils.unescape_path(basename))
      TagLib::FileRef.open(fsPath) do |fileref|
        unless fileref.null?
          tag = fileref.tag
          graph << RDF::Statement.new(self, Title.R, tag.title)
          graph << RDF::Statement.new(self, Creator.R, tag.artist)
          graph << RDF::Statement.new(self, Date.R, tag.year) unless !tag.year || tag.year == 0
          graph << RDF::Statement.new(self, Content.R, tag.comment)
          graph << RDF::Statement.new(self, (Schema+'album').R, tag.album)
          graph << RDF::Statement.new(self, (Schema+'track').R, tag.track)
          graph << RDF::Statement.new(self, (Schema+'genre').R, tag.genre)
          graph << RDF::Statement.new(self, (Schema+'length').R, fileref.audio_properties.length_in_seconds)
        end
      end
    end
  end

  module HTML
    MarkupPredicate[Audio] = -> as, env {as.map{|a| Markup[Audio][a, env]}}

    Markup[Audio] = -> audio, env {
      if audio.class == Hash
        audio = audio['https://schema.org/url'] || audio[Schema+'contentURL'] || audio[Schema+'url'] || audio[Link] || audio['uri']
        (Console.logger.warn "no audio URI!"; audio = '#audio') unless audio
      end

      if audio.class == Array
        Console.logger.warn ["multiple audio files: ", audio].join if audio.size > 1
        audio = audio[0]
        (Console.logger.warn "no audio reference!"; audio = '#audio') unless audio
      end

      src = env[:base].join(audio).R env
      {_: :audio, src: src.uri, controls: :true}}
  end

end
