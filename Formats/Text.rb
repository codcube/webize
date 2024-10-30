# coding: utf-8

# enable 🐢 extension for text/turtle
RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl]

class String

  # text -> HTML, yielding inlined-resource (rel,href) tuples to block
  def hrefs &blk
    # URIs are sometimes wrapped in (). an opening/closing pair is required for capture of (), '"<> never captured. , and . can be used anywhere but end of URL
    pre, link, post = self.partition(/((g(emini|opher)|https?):\/\/(\([^)>\s]*\)|[,.]\S|[^\s),.”\'\"<>\]])+)/)
    pre.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;') + # pre-match
      (link.empty? && '' ||
       '<a href="' + link.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;') + '">' +
       (resource = Webize::Resource.new(link).relocate
        img = nil
        if blk
          type = case link
                 when /[\.=](gif|jpg|jpeg|(jpg|png):(large|small|thumb)|png|webp)([\?&]|$)/i
                   img = '<img src="' + resource.uri + '">'
                   Webize::Image
                 when /(youtu.?be|(mkv|mp4|webm)(\?|$))/i
                   Webize::Video
                 end
          yield type, resource if type
        end
        [img,
         CGI.escapeHTML(resource.uri.sub(/^http:../,'')[0..79])].join) +
       '</a>') +
      (post.empty? && '' || post.hrefs(&blk)) # possibly not tail-recursive, getting stack-overflow on long logs, TODO investigate
  rescue
    logger.warn "failed to scan string for hrefs"
    logger.debug self
    ''
  end

end

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
        text_triples{|s, p, o, graph=nil|
          fn.call RDF::Statement.new(s, p, o,
                                     graph_name: graph || @base)}
      end

      def text_triples &f
        basename = File.basename (@base.path || '/'), '.txt'
        if basename == 'twtxt'
          twtxt_triples &f
        elsif File.extname(@base) == '.irc'
          chat_triples &f
        else
          dom = {_: :pre,
                 c: @doc.lines.map{|line|
                   line.hrefs{|p,o|
                     yield @base, p, o}}}

          html = HTML.render dom

          fragment = HTML::Reader.new(html, base_uri: @base).scan_fragment &f

          yield @base, RDF::URI(Contains), fragment
        end
      end
    end
  end
end
