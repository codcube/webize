module Webize
  module PDF
    class Format < RDF::Format
      content_type 'application/pdf', :extension => :pdf
      reader { Reader }
    end
    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R
        @body = input.respond_to?(:read) ? input.read : input
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
        IO.popen(['pdftohtml', '-s', '-stdout', '-', @base.fsPath.sub(/\.pdf$/,'')], 'r+'){|io|
          io.puts @body
          io.close_write
          html = RDF::Literal Webize::HTML.format io.read, @base
          html.datatype = RDF.XMLLiteral
          yield Content.R, html }
      end
    end
  end
end
