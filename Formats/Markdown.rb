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
        @base = options[:base_uri]
        @options = options
        @html = HTML::Reader.new(                                        # initialize HTML reader
          ::Redcarpet::Markdown.new(Renderer, fenced_code_blocks: true). # initialize Markdown -> HTML transformer
            render(input.respond_to?(:read) ? input.read : input), base_uri: options[:base_uri]) # Markdown -> HTML

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
        fragment = @html.scan_fragment{|s, p, o, graph = @base|
          fn.call RDF::Statement.new(s, Webize::URI(p), o, graph_name: graph)}

        fn.call RDF::Statement.new(@base, Webize::URI(Contains), fragment, graph_name: @base)
      end
    end
  end
end
