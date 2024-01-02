# coding: utf-8
require 'rouge'
module Webize
  module Code
    SiteJS = Webize.configData 'scripts/site.js'

    class Format < RDF::Format
      content_type 'application/ruby',
                   aliases: %w(
                   application/x-sh;q=0.2
                   text/css;q=0.2
                   text/x-c;q=0.8
                   text/x-perl;q=0.8
                   text/x-ruby;q=0.8
                   text/x-script.ruby;q=0.8
                   text/x-shellscript;q=0.8
                   text/yaml;q=0.8
                   ),
                   extensions: [:bash, :c, :css, :cpp, :erb, :gemspec, :go, :h, :hs, :mk, :nim, :nix, :patch, :pl, :pm, :proto, :py, :rb, :sh, :yaml, :zsh]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
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

      def highlight
        # Rouge setup
        if lexer = Rouge::Lexer.find_fancy(@base.extname[1..-1]) rescue nil
          Rouge::Formatters::HTMLPygments.new(Rouge::Formatters::HTML.new).format(lexer.lex(@doc))
        else
          logger.warn "can't determine lexer for #{@base}"
        end
      end

      def source_tuples
        html = RDF::Literal [highlight,
                             '<style>', CSS::Code, '</style>'
                            ].join.encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        html.datatype = RDF.XMLLiteral
        yield RDF::URI(Content), html
      end
    end
  end

  module JS

    class Format < Code::Format
      content_type 'application/javascript',
                   aliases: %w(application/x-javascript;q=0.2
                               text/javascript;q=0.2),
                   extensions: [:js]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < Code::Reader

      def highlight

        # FIX infinite loop at /usr/lib/ruby/gems/3.2.0/gems/rouge-4.1.3/lib/rouge/regex_lexer.rb:361
        return if %w(static.cdninstagram.com www.youtube.com).member?(@base.host) || @doc.size > 1e6

        lexer = Rouge::Lexers::Javascript.new
        Rouge::Formatters::HTMLPygments.new(Rouge::Formatters::HTML.new).format(lexer.lex(@doc))
      end

    end
  end
end
