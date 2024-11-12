# coding: utf-8
module Webize
  module MSWord
    class Format < RDF::Format
      content_type 'application/msword', extensions: [:doc, :docx]
      content_encoding 'utf-8'
      reader { Reader }
    end
    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @path = options[:path] || @base.fsPath
        @options = options
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
        source_tuples{|p,o|
          fn.call RDF::Statement.new(@base, p, o, :graph_name => @base)}
      end

      def source_tuples
        converter = File.extname(@path) == '.doc' ? :antiword : :docx2txt
        html = RDF::Literal '<pre>' + `#{converter} #{Shellwords.escape @path}` + '</pre>'
        html.datatype = RDF.XMLLiteral
        yield RDF::URI(Contains), html
      end
    end
  end

  module NFO
    class Format < RDF::Format
      content_type 'text/nfo', :extension => :nfo
      content_encoding 'utf-8'
      reader { Reader }
    end
    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).force_encoding('CP437').encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        @base = options[:base_uri]
        @options = options
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
        nfo_triples{|p,o|
          fn.call RDF::Statement.new(@base, RDF::URI(p), o,
                                     :graph_name => @base)}
      end

      def nfo_triples
        yield Contains, HTML.render({_: :pre, c: @doc})
      end
    end
  end

  module Plaintext
    class Format < RDF::Format
      content_type 'text/plain', :extensions => [:conf, :irc, :log, :txt]
      content_encoding 'utf-8'
      reader { Reader }
    end
    class Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        @base = options[:base_uri]
        @options = options
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
        triples{|s, p, o, graph=nil|
          fn.call RDF::Statement.new(s, p, o,
                                     graph_name: graph || @base)}
      end

      def triples &f
        if File.basename((@base.path||'/'), '.txt') == 'twtxt'
          twtxt_triples &f
        elsif File.extname(@base) == '.irc'
          chat_triples &f
        else
          plaintext_triples &f
        end
      end

      def plaintext_triples &f
        yield @base, RDF::URI(Contains),           # content pointer
              HTML::Reader.new(                    # instantiate HTML reader
                ['<pre>',                          # wrap in <pre>
                 CGI.escapeHTML(@doc).             # escape text
                   gsub(::URI.regexp,
                        '<a href="\0">\0</a>'),    # href-ize URIs
                 '</pre>'].join,                   # emit HTML
                base_uri: @base).scan_fragment(&f) # webize HTML
      end

    end
  end
end
