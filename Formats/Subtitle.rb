module Webize
  module VTT
    class Format < RDF::Format
      content_type 'text/vtt', :extension => :vtt
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      ENV['BUNDLE_GEMFILE'] = File.expand_path '../Gemfile', File.dirname(__FILE__)
      def initialize(input = $stdin, options = {}, &block)
        require 'bundler'
        Bundler.setup
        require "webvtt"

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
        vtt_triples{|s,p,o|
          fn.call RDF::Statement.new(s, RDF::URI(p),
                                     (o.class == Webize::URI || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @base)}
      end

      def vtt_triples
        webvtt = @base.host ? WebVTT.from_blob(@doc) : WebVTT.read(@base.fsPath)
        line = 0
        webvtt.cues.each do |cue|
          subject = @base.join '#l' + line.to_s; line += 1
          yield subject, Type, RDF::URI(Post)
          yield subject, Date, cue.start
          yield subject, Content, cue.text
        end
      end
    end
  end
end
