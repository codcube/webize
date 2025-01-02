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
        network, channame = @base.basename.split '.'
        channame = Rack::Utils.unescape_path(channame).gsub('#','')
        chan = @base + '#' + channame
        day_slug = parts[0..2].join('-') + 'T'
        hourslug = parts[0..3].join
        lines = 0
        ts = {}

        # query arguments
        text_query = @base.env[:qs]['q']&.downcase    # general text search
        from_query = @base.env[:qs]['from']&.downcase # from: constraint

        # show only link/image-containing lines in preview mode
        text_query = 'http' if @base.env[:preview] && !text_query && !from_query

        @doc.lines.grep(/^[^-]/).map{|msg|

          # line must match if query argument provided
          next if text_query &&
                  !msg.downcase.index(text_query)

          tokens = msg.split /\s+/         # tokenize

          time = tokens.shift              # timestamp
          next if tokens.empty?

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

          next if from_query && # skip line not tmatching from: query
                  nick.downcase != from_query

          timestamp = day_slug + time
          subject = RDF::URI ['#', channame, hourslug, lines += 1].join

          yield subject, RDF::URI(Type), type                    # typetag
          yield chan, RDF::URI(Schema+'item'), RDF::URI(subject) # line entry

          ts[timestamp] ||= 0                                    # timestamp
          yield subject, RDF::URI(Date), [timestamp, '%02d' % ts[timestamp]].join('.')
          ts[timestamp] += 1

          creator = @base + '?from=' + nick + '#' + nick         # author
          yield subject, RDF::URI(Creator), creator

          Plaintext::Reader.new(msg, base_uri: @base).           # line content
            plaintext_triples(subject, &f) if msg}

        return unless lines > 0 # skip channel metadata for empty logs

        yield @base, RDF::URI(Contains), chan
        yield chan, RDF::URI(Title), '#' + channame
        yield chan, RDF::URI(Abstract), [File.basename(hour), ':00'].join
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
          Plaintext::Reader.new(msg, base_uri: subject).plaintext_triples(&f) if msg
          yield subject, Creator, (@base.host + dirname).split(/\W/).join('.'), graph
          yield subject, To, @base, graph
        }
      end
    end
  end
end
