# coding: utf-8
module Webize
  module Plaintext

    class Reader < RDF::Reader

      # IRC log -> RDF
      def chat_triples &f
        # irssi:
        #  /set autolog on
        #  /set autolog_path ~/web/%Y/%m/%d/%H/$tag.$0.irc
        # weechat:
        #  /set logger.mask.irc "%Y/%m/%d/%H/$server.$channel.irc"

        type = RDF::URI(SIOC + 'InstantMessage')
        parts = @base.parts
        hour = File.dirname @base.path
        day = File.dirname hour
        month = File.dirname day
        year = File.dirname month
        network, channame = @base.basename.split '.'
        channame = Rack::Utils.unescape_path(channame).gsub('#','')
        chan = @base + '#' + channame
        day_slug = parts[0..2].join('-') + 'T'
        hourslug = parts[0..3].join
        lines = 0
        ts = {}

        # query arguments
        text_query = @base.env[:qs]['q']&.downcase
        from_query = @base.env[:qs]['from']&.downcase

        @doc.lines.grep(/^[^-]/).map{|msg|
          next if text_query && # skip chat line not matching query argument
                  !msg.downcase.index(text_query)

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

          next if from_query && # skip line nott tmatching from: query
                  nick.downcase != from_query

          timestamp = day_slug + time
          subject = RDF::URI ['#', channame, hourslug, lines += 1].join
          yield subject, RDF::URI(Type), type
          yield chan, RDF::URI(Schema+'item'), RDF::URI(subject)
          ts[timestamp] ||= 0
          yield subject, RDF::URI(Date), [timestamp, '%02d' % ts[timestamp]].join('.')
          ts[timestamp] += 1
          creator = RDF::URI(day + '/*/*irc?q=' + nick + '&sort=date&view=table#' + nick)
          yield subject, RDF::URI(Creator), creator
          yield subject, RDF::URI(Contains),
                HTML::Reader.new(msg.hrefs, base_uri: @base).scan_fragment(&f) if msg}

        return unless lines > 0

        yield @base.env[:base], RDF::URI(Contains), RDF::URI(year)
        yield RDF::URI(year), RDF::URI(Title), File.basename(year)
        yield RDF::URI(year), RDF::URI(Contains), RDF::URI(month)
        yield RDF::URI(month), RDF::URI(Title), File.basename(month)
        yield RDF::URI(month), RDF::URI(Abstract), ::Date::MONTHNAMES[File.basename(month).to_i]
        yield RDF::URI(month), RDF::URI(Contains), RDF::URI(day)
        yield RDF::URI(day), RDF::URI(Title), File.basename(day)
        yield RDF::URI(day), RDF::URI(Contains), chan
        yield chan, RDF::URI(Title), '#' + channame
        yield chan, RDF::URI(Type), RDF::URI('http://rdfs.org/sioc/ns#ChatLog')

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
