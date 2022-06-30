# coding: utf-8
%w(exif).map{|_| require _}
module Webize
  module GIF
    class Format < RDF::Format
      content_type 'image/gif', :extension => :gif, aliases: %w(image/GIF;q=0.8)
      reader { Reader }
    end

    class Reader < RDF::Reader
      include Console
      include WebResource::URIs
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

    # alternate names for src and srcset attributes

    SRCnotSRC = %w(
data-baseurl
data-delayed-url
data-ezsrc
data-gl-src
data-hi-res-src
data-image
data-img
data-img-url
data-img-src
data-lazy
data-lazy-img
data-lazy-src
data-menuimg
data-native-src
data-original
data-raw-src
data-src
data-url
image-src
)

    SRCSET = %w{
data-ezsrcset
data-gl-srcset
data-lazy-srcset
data-srcset
}

    SrcSetRegex = /\s*(\S+)\s+([^,]+),*/

    # resolve @srcset refs
    def self.srcset node, base
      srcset = node['srcset'].scan(SrcSetRegex).map{|url, size|[(base.join url), size].join ' '}.join(', ')
      if srcset.empty?
        Console.logger.warn "srcset failed to parse: " + node['srcset']
      else
        node['srcset'] = srcset
      end
    end

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
      include Console
      include WebResource::URIs
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
                                     (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
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
      content_type 'image/png', :extensions => [:ico, :png]
      reader { Reader }
    end

    class Reader < RDF::Reader
      include Console
      include WebResource::URIs
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
          fn.call RDF::Statement.new(@subject, p, (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
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
      include Console
      include WebResource::URIs
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
          fn.call RDF::Statement.new(@subject, p, (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples

      end

    end
  end
end
class WebResource

  module HTML

    MarkupPredicate[Schema+'srcSet'] = -> sets, env {
      sets.map{|set|
        set.to_s.scan(Webize::HTML::SrcSetRegex).map{|ref, _|
          Markup[Image][ref, env]}}}

    MarkupPredicate[Image] = -> images, env {
      {class: :images, c: images.map{|i|
         Markup[Image][i,env]}}}

    Markup[Image] = -> image, env {
      if image.class == Hash
        resource = image.dup
        image = image['https://schema.org/url'] || image[Schema+'url'] || image[Link] || image['uri']
        (Console.logger.warn "no image URI!"; image = '#image') unless image
      end

      if image.class == Array
        Console.logger.warn ['multiple images: ', image].join if image.size > 1
        image = image[0]
        (Console.logger.warn "empty image resource"; image = '#image') unless image
      end

      src = env[:base].join(image).R(env).href
      {c: [{_: :a, href: src,
            c: {_: :img, src: src}},
           (['<br>',
             {class: :abstract,
              c: resource[Abstract].map{|a|
                [(markup a,env),' ']}}] if resource&.has_key? Abstract)]}}

  end
end
