# coding: utf-8
module Webize
  module HTML
    class Reader

      # initialize {CSS selector -> RDF attribute} map
      MsgCSS = {}

      # load user-defined maps
      %w(
 content
 creator
 creatorHref
 date
 gunk
 image imageP imagePP
 link
 post
 reply
 title
 video
).map{|a|
        MsgCSS[a.to_sym] = Webize.configList('metadata/CSS/' + a).join ', '}

    end
  end
  module Plaintext

    class Reader < RDF::Reader

      # IRC log -> RDF
      def chat_triples
        # irssi:
        #  /set autolog on
        #  /set autolog_path ~/web/%Y/%m/%d/%H/$tag.$0.irc
        # weechat:
        #  /set logger.mask.irc "%Y/%m/%d/%H/$server.$channel.irc"

        type = (SIOC + 'InstantMessage').R
        parts = @base.parts
        dirname = File.dirname @base.path
        daydir = File.dirname dirname
        network, channame = @base.basename.split '.'
        channame = Rack::Utils.unescape_path(channame).gsub('#','')
        target = @base + '#' + channame
        day = parts[0..2].join('-') + 'T'
        hourslug = parts[0..3].join
        linkgroup = [nil, parts[0..2]].join('/') + '/#IRClinks'
        lines = 0
        ts = {}

        yield target, Type, Container.R
        yield target, Type, 'http://rdfs.org/sioc/ns#ChatLog'.R

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
          subject = '#' + channame + hourslug + (lines += 1).to_s
          yield subject, Type, type
          yield target, Contains, subject.R
          ts[timestamp] ||= 0
          yield subject, Date, [timestamp, '%02d' % ts[timestamp]].join('.')
          ts[timestamp] += 1
          yield subject, To, target
          creator = (daydir + '/*/*irc?q=' + nick + '&sort=date&view=table#' + nick).R
          yield subject, Creator, creator
          yield subject, Content, ['<pre>',
                                   msg.hrefs{|p,o| yield [Image,Video].member?(p) ? subject : linkgroup, p, o}, # cluster non-media links per channel for space-efficient layout
                                   '</pre>'].join if msg}
      end

      # twtxt -> RDF
      def twtxt_triples
        dirname = File.dirname @base.path
        @doc.lines.grep(/^[^#]/).map{|line|
          date, msg = line.split /\t/
          graph = @base.join (dirname == '/' ? '' : dirname) + '/twtxt.' + date.gsub(/\D/,'.')
          subject = graph.join '#msg'
          yield subject, Type, Post.R, graph
          yield subject, Date, date, graph
          yield subject, Content, Webize::HTML.format(msg.hrefs, @base), graph if msg
          yield subject, Creator, (@base.host + dirname).split(/\W/).join('.'), graph
          yield subject, To, @base, graph
        }
      end
    end
  end
  module HTML

    # message sender
    MarkupPredicate[Creator] = MarkupPredicate['http://xmlns.com/foaf/0.1/maker'] = -> creators, env {
      creators.map{|creator|
        if [Webize::URI, Webize::Resource, RDF::URI].member? creator.class
          uri = Webize::Resource.new(creator).env env
          name = uri.display_name
          color = Digest::SHA2.hexdigest(name)[0..5]
          {_: :a, class: :from, href: uri.href, style: "background-color: ##{color}", c: name}
        else
          markup creator, env
        end}}

    # message receiver
    MarkupPredicate[To] = -> recipients, env {
      recipients.map{|r|
        if [Webize::URI, Webize::Resource, RDF::URI].member? r.class
          uri = Webize::Resource.new(r).env env
          name = uri.display_name
          color = Digest::SHA2.hexdigest(name)[0..5]
          {_: :a, class: :to, href: uri.href, style: "background-color: ##{color}", c: ['&rarr;', name].join}
        else
          markup r, env
        end}}

    Markup[Schema + 'InteractionCounter'] = -> counter, env {
      if type = counter[Schema+'interactionType']
        type = type[0].to_s
        icon = Icons[type] || type
      end
      {_: :span, class: :interactionCount,
       c: [{_: :span, class: :type, c: icon},
           {_: :span, class: :count, c: counter[Schema+'userInteractionCount']}]}}

  end
end
