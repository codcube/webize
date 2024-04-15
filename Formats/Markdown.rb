#require 'kramdown'
require 'redcarpet'
require 'rouge/plugins/redcarpet'

module Webize
  module Markdown

    class Renderer < Redcarpet::Render::HTML
      include Rouge::Plugins::Redcarpet
    end

    class Format < RDF::Format
      content_type 'text/markdown', :extensions => [:markdown, :md, :MD]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @base = options[:base_uri]
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
        markdown_triples{|s,p,o|
          fn.call RDF::Statement.new(s, p, ((o = RDF::Literal o).datatype = RDF.HTML; o),
                                     :graph_name => @subject)}
      end

      def markdown_triples
        yield @base, RDF::URI(Content), ::Redcarpet::Markdown.new(Renderer, fenced_code_blocks: true).render(@doc)
      end
    end
  end

end
