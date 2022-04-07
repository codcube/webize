# coding: utf-8
require 'rouge'
module Webize
  module Code
    include WebResource::URIs

    class Format < RDF::Format
      content_type 'application/ruby',
                   aliases: %w(
                   application/javascript;q=0.2
                   application/x-javascript;q=0.2
                   application/x-sh;q=0.2
                   text/css;q=0.2
                   text/javascript;q=0.8
                   text/x-c;q=0.8
                   text/x-perl;q=0.8
                   text/x-ruby;q=0.8
                   text/x-script.ruby;q=0.8
                   text/x-shellscript;q=0.8
                   ),
                   extensions: [:bash, :c, :css, :cpp, :erb, :gemspec, :go, :h, :hs, :js, :mk, :nim, :nix, :patch, :pl, :pm, :proto, :py, :rb, :sh, :zsh]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R
        @doc = (input.respond_to?(:read) ? input.read : input).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '

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
        yield Type.R, (Schema + 'Code').R
        yield Title.R, @base.basename if @base.basename

        # Rouge
        if lexer = Rouge::Lexer.guess_by_filename(@base.basename) rescue nil
         # puts "rouge #{lexer} #{@base.basename}"
          html = Rouge::Formatters::HTMLPygments.new(Rouge::Formatters::HTML.new).format(lexer.lex(@doc))
        else
          puts "can't determine lexer for #{@base}"
        end

        html = RDF::Literal [html,
                             '<style>', CodeCSS, '</style>'
                            ].join.encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        html.datatype = RDF.XMLLiteral
        yield Content.R, html
      end
    end
  end
end
