module Webize
  module Gemini
    class Format < RDF::Format
      content_type 'text/gemini', :extensions => [:gmi]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      Heading = /^#+/
      Link = /^=>/
      Bullet = /^\*\s*/
      Pre = /^```/
      Quote = /^>[\s>]*/

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
        gemtext_triples{|s,p,o|
          fn.call RDF::Statement.new(s, RDF::URI(p), o,
                                     :graph_name => @subject)}
      end

      def gemtext_triples
        lines = @doc.lines
        in_pre = false
        videos = []

        if title = lines.find{|line| line.match /^#[^#]/}
          yield @base, Title, title.sub(Heading, '')
        end

        yield @base, Contains,
              lines.map{|line|
          line.chomp!
          case line
          when Heading
            depth = line.match(Heading).size
            HTML.render(
              {_: [:h, depth].join,
               c: CGI.escapeHTML(line.sub(Heading, ''))})
          when Link
            _, uri, title = line.split /\s+/, 3
            uri = RDF::URI(@base.join uri)
            videos.push uri if %w{www.youtube.com}.member? uri.host
            [HTML.render(
               {_: :a, href: uri,
                c: [uri.imgURI? ? {_: :img, src: uri} : nil,
                    CGI.escapeHTML(title || uri.to_s)]}), " \n"]
          when Bullet
            HTML.render(
              {_: :ul,
               c: {_: :li,
                   c: CGI.escapeHTML(line.sub(Bullet, ''))}})
          when Pre
            if in_pre
              in_pre = false
              '</code>'
            #'</pre>'
            else
              in_pre = true
              '<code>'
              #'<pre>'
            end
          when Quote
            ['<blockquote>',
             CGI.escapeHTML(line.sub(Quote, '')),
             '</blockquote>']
          else
            [CGI.escapeHTML(line), in_pre ? nil : '<br>', "\n"]
          end
        }.join

        videos.map{|video|
          yield video, Type, RDF::URI(Video)}
      end
    end
  end

end
