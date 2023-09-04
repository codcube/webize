# coding: utf-8
#%w(exif).map{|_| require _}
module Webize
  module GIF
    class Format < RDF::Format
      content_type 'image/gif',
                   extension: :gif,
                   aliases: %w(
                   image/avif;q=0.2
                   image/GIF;q=0.8)
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R
        @img = Exif::Data.new(input.respond_to?(:read) ? input.read : input) rescue nil
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

    # load alternate names for src and srcset attributes
    SRCnotSRC = Webize.configList 'formats/image/src'
    SRCSET = Webize.configList 'formats/image/srcset'
    SrcSetRegex = /\s*(\S+)\s+([^,]+),*/

    # resolve @srcset refs
    def self.srcset node, base
      srcset = node['srcset'].scan(SrcSetRegex).map{|url, size|
        [(base.join url), size].join ' '
      }.join(', ')
      srcset = base.join node['srcset'] if srcset.empty? # resolve singleton URL in srcset attribute. eithere there's lots of spec violators or this is allowed. we allow it 
      node['srcset'] = srcset
    end

    MarkupPredicate[Image] = -> images, env {
      images.map{|i|
        Markup[Image][ i.class == Hash ? i : {'uri' => i.to_s}, env ]}}

    Markup[Image] = -> image, env {
      src = Webize::Resource((env[:base].join image['uri']), env).href

      [{class: :image,
        c: [{_: :a, href: src,
             c: {_: :img, src: src}},
            (['<br>', {class: :caption,
               c: image[Abstract].map{|a|
                 [(markup a,env),' ']}}] if image.has_key? Abstract),
            ([Abstract,Image,Type,'uri'].map{|p| image.delete p }
             HTML.keyval(image, env) unless image.empty?)]}, ' ']}

  end
  module JPEG
    class Format < RDF::Format
      content_type 'image/jpeg',
                   extensions: [:jpeg, :jpg, :JPG],
                   aliases: %w(
                   image/jpg;q=0.8
                   image/pjpeg;q=0.2
)
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R 
#        @img = Exif::Data.new(input.respond_to?(:read) ? input.read : input) rescue nil
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
        return # EXIF segfaulting, investigate.. or use perl exiftool?
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject,
                                     p.R,
                                     (o.class == Webize::URI || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples
        yield Image, @subject
        [:ifd0, :ifd1, :exif, :gps].map{|fields|
          @img[fields].map{|k,v|
            if k == :date_time
              yield Date, Time.parse(v.sub(':','-').sub(':','-')).iso8601 rescue nil
            else
              yield ('http://www.w3.org/2003/12/exif/ns#' + k.to_s), v.to_s.encode('UTF-8', undef: :replace, invalid: :replace, replace: '?')
            end
          }} if @img
      end
      
    end
  end
  module PNG
    class Format < RDF::Format
      content_type 'image/png',
                   extensions: [:png, :ico],
                   aliases: %w(
                   image/x-icon;q=0.8
                   image/vnd.microsoft.icon;q=0.2
)
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
         @subject = (options[:base_uri] || '#image').R 
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
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject, p, (o.class == Webize::URI || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples

      end

    end
  end
  module WebP
    class Format < RDF::Format
      content_type 'image/webp', :extension => :webp
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R 
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
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject, p, (o.class == Webize::URI || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples

      end

    end
  end
end
