# coding: utf-8

class String

  # text -> HTML, yielding found (rel, href) tuples to block
  def hrefs &blk
    # URIs are sometimes wrapped in (). an opening/closing pair is required for capture of (), '"<> never captured. , and . can appear in URL but not at the end
    pre, link, post = self.partition(/((g(emini|opher)|https?):\/\/(\([^)>\s]*\)|[,.]\S|[^\s),.”\'\"<>\]])+)/)
    pre.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub("\n",'<br>') + # pre-match
      (link.empty? && '' ||
       '<a href="' + link.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;') + '">' +
       (resource = link.R
        img = nil
        if blk
          type = case link
                 when /[\.=](gif|jpg|jpeg|(jpg|png):(large|small|thumb)|png|webp)([\?&]|$)/i
                   img = '<img src="' + resource.uri + '">'
                   WebResource::Image
                 when /(youtu.?be|(mkv|mp4|webm)(\?|$))/i
                   WebResource::Video
                 else
                   WebResource::Link
                 end
          yield type, resource
        end
        [img,
         CGI.escapeHTML(resource.uri.sub(/^http:../,'')[0..79])].join) +
       '</a>') +
      (post.empty? && '' || post.hrefs(&blk)) # prob not tail-recursive, getting overflow on logfiles, may need to rework
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
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @path = options[:path] || @base.fsPath
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
        yield Type.R, (Schema + 'Document').R
        yield Title.R, @base.basename if @base.basename
        converter = File.extname(@path) == '.doc' ? :antiword : :docx2txt
        html = RDF::Literal '<pre>' + `#{converter} #{Shellwords.escape @path}` + '</pre>'
        html.datatype = RDF.XMLLiteral
        yield Content.R, html
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
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).force_encoding('CP437').encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        @base = options[:base_uri].R
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
          fn.call RDF::Statement.new(@base, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @base)}
      end

      def nfo_triples
        yield Content, WebResource::HTML.render({_: :pre, c: @doc})
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
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        @base = options[:base_uri].R
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
          fn.call RDF::Statement.new(s.R, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     graph_name: graph || @base)}
      end

      def text_triples &f
        basename = File.basename (@base.path || '/'), '.txt'
        if basename == 'twtxt'
          twtxt_triples &f
        elsif File.extname(@base) == '.irc'
          chat_triples &f
        else
          yield @base, Content, Webize::HTML.format(WebResource::HTML.render({_: :pre,
                                                                              c: @doc.lines.map{|line|
                                                                                line.hrefs{|p,o|
                                                                                  yield @base, p, o  unless o.deny?
                                                                                }}}), @base)
        end
      end
    end
  end

end

class WebResource
  module URIs

    BasicSlugs = [nil, '', *%w{2019 2020 2021 2022 2023 2024 2025 2026 2027 2028 2029
 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
 a account accounts alerts amp and anonymous api article archives articles as at atom
 blog blogger blogs blogspot boards
 channel columns co com comment comments content
 default edu email en entry episode episodes
 feed feedburner feeds feedproxy format forum forums
 g gmail gne go gov
 html http https id in index irc is item
 lang link lists local
 mail mailto media medium msg
 net news node noreply nospam notifications
 of org
 p people photos php post posts profile protonmail public
 r reddit reply res rs rss rssfeed
 s section sendgrid sports source status statuses story
 t tag the thread threads to top topic tracks type
 uk uploads us user users utm
 v videos
 watch wordpress wp www xml}]

    # plaintext MIME hint for names without extensions, avoids FILE(1) call
    TextFiles = %w(changelog copying license readme todo)

    def slugs
      re = /[\W_]/
      [(host&.split re),
       parts.map{|p| p.split re},
       (query&.split re),
       (fragment&.split re)]
    end
  end
end
