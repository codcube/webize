# coding: utf-8
module Webize
  module ArchiveFile
    class Format < RDF::Format
      content_type 'application/gzip',
                   aliases: %w(
                   application/x-bzip2;q=0.8
                   application/x-gzip;q=0.8
                   application/x-tar;q=0.8
                   application/x-xz;q=0.8
                   application/gzip;q=0.8
                   application/zip;q=0.8
),
                   extensions: [:apk,
                                :gz,
                                :tar,
                                :tgz,
                                :xz,
                                :zst]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @options = options
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = RDF::URI(options[:base_uri] || '#zip')
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
        archive_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, RDF::URI(p), o,
                                     :graph_name => @subject)}
      end

      def archive_triples
      end
    end
  end
end
