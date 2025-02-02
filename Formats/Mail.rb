# coding: utf-8
require 'mail'
module Webize
  module Mail
    class Format < RDF::Format
      content_type 'message/rfc822',
                   aliases: %w(message/rfc2822;q=0.8),
                   extension: :eml
      content_encoding 'utf-8'
      reader { Reader }
      def self.symbols
        [:mail]
      end
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @options = options
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
        mail_triples(@doc){|subject, predicate, o, graph = @base|
          fn.call RDF::Statement.new(subject, Webize::URI(predicate), o,
                                     graph_name: graph)}
      end

      def mail_triples body, &b
        m = ::Mail.new body
        return logger.warn "email parse failed #{@base}" unless m

        # Message resource
        id = m.message_id || m.resent_message_id || Digest::SHA2.hexdigest(rand.to_s)
        # we'd like to emit pure mid: but it's looping inside /data/data/com.termux/files/usr/lib/ruby/gems/3.3.0/gems/rdf-3.3.2/lib/rdf/model/uri.rb on serialization with URis like mid:../ and adding another ../ each time. not sure what's up.. 
        mail = graph = RDF::URI( '/' + POSIX::Node('mid:' + Rack::Utils.escape_path(id)).fsPath )

        # query args
        from_query = @base.env[:qs]['from']&.downcase
        from_text = [m.from, m[:from]].join.downcase
        return if from_query && !from_text.index(from_query)

        # RDF type
        yield mail, Type, RDF::URI(SIOC + 'MailMessage'), graph

        # From
        m.from.yield_self{|f|
          ((f.class == Array || f.class == ::Mail::AddressContainer) ? f : [f]).compact.map{|f|
            noms = f.split ' '
            f = "#{noms[0]}@#{noms[2]}" if noms.size > 2 && noms[1] == 'at'
            yield mail, Creator, RDF::URI('/mailto/' + f), graph
          }}

        m[:from] && m[:from].yield_self{|fr|
          fr.addrs.map{|a|
            name = a.display_name || a.name # human-readable name
            yield mail, Creator, name, graph if name
          } if fr.respond_to? :addrs}

        # To
        %w{to cc bcc resent_to}.map{|p|      # recipient accessor-methods
          m.send(p).yield_self{|r|           # recipient(s)
            ((r.class == Array || r.class == ::Mail::AddressContainer) ? r : [r]).compact.map{|r| # recipient
              yield mail, To, RDF::URI('/mailto/' + r), graph
            }}}

        m['X-BeenThere'].yield_self{|b|      # anti-loop recipient property
          (b.class == Array ? b : [b]).compact.map{|r|
            r = r.to_s
            yield mail, To, RDF::URI('/mailto/' + r), graph
          }}

        m['List-Id'] && m['List-Id'].yield_self{|name|
          yield mail, To, name.decoded.sub(/<[^>]+>/,'').gsub(/[<>&]/,''), graph} # mailinglist name

        # Subject
        subject = nil
        m.subject && m.subject.yield_self{|s|
          subject = s
          subject.scan(/\[[^\]]+\]/){|l|
            yield mail, Schema + 'group', l[1..-2], graph}
          yield mail, Title, subject, graph}

        # Date
        if date = m.date
          timestamp = ([Time, DateTime].member?(date.class) ? date : Time.parse(date.to_s)).iso8601
          yield mail, Date, timestamp, graph
        end

        # HTML parts
        htmlParts, parts = m.all_parts.push(m).partition{|p|
          p.mime_type == 'text/html' }

        htmlParts.map{|p|
          HTML::Reader.new(p.decoded, base_uri: mail).scan_document &b}

        # plaintext parts
        textParts, parts = parts.partition{|p|
          (!p.mime_type || p.mime_type.match?(/^text\/plain/)) && # text and untyped parts
            ::Mail::Encodings.defined?(p.body.encoding)}          # decodable?

        textParts.map{|p|
          Plaintext::Reader.new(p.decoded, base_uri: mail).plaintext_triples &b}

        # recursive mail parts: digests, forwards, archives
        mailParts, parts = parts.partition{|p|
          p.mime_type=='message/rfc822'}

        mailParts.map{|m|
          mail_triples m.body.decoded, &b}

        # attachments
        attachments = m.attachments

        attachments.select{|p|
          ::Mail::Encodings.defined?(p.body.encoding)}.map{|p|     # decodability check
          name = p.filename && !p.filename.empty? && p.filename[-64..-1] || # attachment name
                 (Digest::SHA2.hexdigest(rand.to_s) + (Rack::Mime::MIME_TYPES.invert[p.mime_type&.downcase] || '.bin').to_s) # generate name
          file = POSIX::Node RDF::URI('/').join(POSIX::Node(graph).fsPath + '.' + name) # file URI
          unless file.exist?              # store file
            file.write p.body.decoded.force_encoding 'UTF-8'
          end
          yield mail, SIOC+'attachment', file, graph # attachment pointer
          if p.main_type == 'image'           # image attachments
            yield mail, Image, file, graph    # image link in RDF
            yield mail, Contains,             # image link in HTML
                  RDF::Literal(HTML.render({_: :a, href: file.uri, c: [{_: :img, src: file.uri}, p.filename]}), datatype: RDF.HTML), graph # render HTML
          end }

        # remaining parts
        rest = (parts - attachments - [m]).select{|p|
          !p.mime_type || p.mime_type.index('multipart') != 0}

        puts "#{@base} unprocessed mail parts:", rest.map{|p|
          [p.mime_type, p.filename].join "\t"} unless rest.empty?

        # references
        %w{in_reply_to references}.map{|ref|
          m.send(ref).yield_self{|rs|
            (rs.class == Array ? rs : [rs]).compact.map{|r|
              msg = RDF::URI( '/' + POSIX::Node('mid:' + Rack::Utils.escape_path(r)).fsPath )
              yield mail, SIOC + 'reply_of', msg, graph
              yield msg, SIOC + 'has_reply', mail, graph
            }}}

        yield mail, SIOC+'user_agent', m['X-Mailer'].to_s, graph if m['X-Mailer']
      end
    end
  end
end

# TODO mailto handler <https://www.w3.org/DesignIssues/UI.html>:
# A mailto address is a misnomer (my fault I feel as I didn't think when we created it) as it is not supposed to be a verb "start a mail message to this person", it is supposed to be a reference to a web object, a mailbox. So clicking on a link to it should bring up a representation of the mailbox. This for example might include (subject to my preferences) an address book entry and a list of the messages sent to/from [Cc] the person recently to my knowledge. Then I could mail something to someone by linking (dragging) the mailbox icon to or from the document icon. 
