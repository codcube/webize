# coding: utf-8
module Webize
  module Plaintext

    class Reader < RDF::Reader

      # IRC log -> RDF
      def chat_triples
        # irssi:
        #  /set autolog on
        #  /set autolog_path ~/web/%Y/%m/%d/%H/$tag.$0.irc
        # weechat:
        #  /set logger.mask.irc "%Y/%m/%d/%H/$server.$channel.irc"

        type = RDF::URI(SIOC + 'InstantMessage')
        parts = @base.parts
        dirname = File.dirname @base.path
        daydir = File.dirname dirname
        network, channame = @base.basename.split '.'
        channame = Rack::Utils.unescape_path(channame).gsub('#','')
        target = @base + '#' + channame
        day = parts[0..2].join('-') + 'T'
        hourslug = parts[0..3].join
        lines = 0
        ts = {}

        yield @base.env[:base], RDF::URI(Contains), target

        yield target, RDF::URI(Type), RDF::URI('http://rdfs.org/sioc/ns#ChatLog')

        @doc.lines.grep(/^[^-]/).map{|msg|
          tokens = msg.split /\s+/
          time = tokens.shift
          if ['*','-!-'].member? tokens[0] # actions, joins, parts
            nick = tokens[1]
            msg = tokens[2..-1].join ' '
            msg = '/me ' + msg if tokens[0] == '*'
          elsif tokens[0].match? /^-.*:.*-$/ # notices
            nick = tokens[0][1..tokens[0].index(':')-1]
            msg = tokens[1..-1].join ' '
          elsif re = msg.match(/<[\s@+*]*([^>]+)>\s?(.*)?/)
            nick = re[1]
            msg = re[2]
          end
          nick = CGI.escape(nick || 'anonymous')
          timestamp = day + time
          subject = RDF::URI ['#', channame, hourslug, lines += 1].join
          yield subject, RDF::URI(Type), type
          yield target, RDF::URI(Schema+'item'), RDF::URI(subject)
          ts[timestamp] ||= 0
          yield subject, RDF::URI(Date), [timestamp, '%02d' % ts[timestamp]].join('.')
          ts[timestamp] += 1
          yield subject, RDF::URI(To), target
          creator = RDF::URI(daydir + '/*/*irc?q=' + nick + '&sort=date&view=table#' + nick)
          yield subject, RDF::URI(Creator), creator
          yield subject, RDF::URI(Contains), RDF::Literal(msg.hrefs, datatype: RDF.HTML) if msg}
      end

      # twtxt -> RDF
      # https://dev.twtxt.net/ https://twtxt.readthedocs.io/
      def twtxt_triples
        dirname = File.dirname @base.path
        @doc.lines.grep(/^[^#]/).map{|line|
          date, msg = line.split /\t/
          graph = @base.join (dirname == '/' ? '' : dirname) + '/twtxt.' + date.gsub(/\D/,'.')
          subject = graph.join '#msg'
          yield subject, Type, RDF::URI(Post), graph
          yield subject, Date, date, graph
          yield subject, Contains, msg.hrefs, graph if msg
          yield subject, Creator, (@base.host + dirname).split(/\W/).join('.'), graph
          yield subject, To, @base, graph
        }
      end
    end
  end
end
