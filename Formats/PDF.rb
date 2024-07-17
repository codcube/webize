module Webize
  module PDF
    class Format < RDF::Format
      content_type 'application/pdf', :extension => :pdf
      reader { Reader }
    end
    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @body = input.respond_to?(:read) ? input.read : input
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
        pdf_tuples{|p,o|
          fn.call RDF::Statement.new(@base, p, o, :graph_name => @base)}
      end

      def pdf_tuples
        IO.popen(['pdftohtml', '-s', '-stdout', '-', POSIX::Node(@base).fsPath.sub(/\.pdf$/,'')], 'r+'){|io|
          io.puts @body
          io.close_write
          html = RDF::Literal io.read
          html.datatype = RDF.XMLLiteral
          yield RDF::URI(Contains), html }
      end
    end
  end
end
