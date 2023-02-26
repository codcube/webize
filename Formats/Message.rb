# coding: utf-8
module Webize
  module HTML
    class Reader

      MsgCSS = {} # {CSS selector -> RDF attribute}
      %w(
 content
 creator
 creatorHref
 date
 freeformDate
 gunk
 image imageP imagePP
 link
 post
 reply
 title
 video).map{|a| # load user-defined maps
        MsgCSS[a.to_sym] = Webize.configList('metadata/CSS/' + a).join ', '}

      DateAttr = %w(data-time data-timestamp data-utc date datetime time timestamp unixtime title)

      def scanMessages
        @doc.css(MsgCSS[:post]).map{|post|                                 # visit post(s)
          links = post.css(MsgCSS[:link])

          subject = if !links.empty?
                      links[0]['href']                                     # identifier in self-referential link
                    else
                      post['data-post-no'] || post['id'] || post['itemid'] # identifier attribute
                    end

          if subject                                                       # identifier found?
            post.css(MsgCSS[:post]).map{|childPost|                        # child posts are emitted separately
              childPost.remove if !childPost.css(MsgCSS[:link]).empty? || childPost['id']}

            subject = @base.join subject                                   # resolve subject URI
            graph = ['//', subject.host, subject.path&.sub(/\.html$/, ''), # resolve graph URI
                     '/', subject.fragment].join.R                         # fragment URI to graph path (posts/replies to their own files)

            yield subject, Type, (SIOC + 'BoardPost').R, graph             # RDF type

            post.css(MsgCSS[:date]).map{|d|                                # ISO8601 and UNIX timestamp
              yield subject, Date, d[DateAttr.find{|a| d.has_attribute? a }] || d.inner_text, graph
              d.remove}

            post.css(MsgCSS[:freeformDate]).map{|created|                  # freeform timestamp
              if date = Chronic.parse(created['data-content'] || created.inner_text)
                yield subject, Date, date.iso8601, graph
                created.remove
              end}

            post.css(MsgCSS[:creator]).map{|name|
              yield subject, Creator, name.inner_text, graph               # author name
              name.remove }

            post.css(MsgCSS[:creatorHref]).map{|a|
             yield subject, Creator, (@base.join a['href']), graph         # author URI
             a.remove }

            post.css(MsgCSS[:title]).map{|subj|
              yield subject, Title, subj.inner_text, graph                 # title
              subj.remove }

            post.css('img').map{|i|
              yield subject, Image, (@base.join i['src']), graph}          # image

            post.css(MsgCSS[:image]).map{|a|
              yield subject, Image, (@base.join a['href']), graph}         # image reference

            post.css(MsgCSS[:imageP]).map{|img|                            # image reference on parent node
              yield subject, Image, (@base.join img.parent['href']), graph }

            post.css(MsgCSS[:imagePP]).map{|img|                           # image reference on grandparent node
              yield subject, Image, (@base.join img.parent.parent['href']), graph }

            post.css(MsgCSS[:video]).map{|a|                               # video
              yield subject, Video, (@base.join a['href']), graph }

            post.css('.comment-comments').map{|c|                          # comment count
              if count = c.inner_text.strip.match(/^(\d+) comments$/)
                yield subject, 'https://schema.org/commentCount', count[1], graph
              end}

            cs = post.css MsgCSS[:content]                                 # content nodes
            cs.push post if cs.empty?

            cs.map{|c|                                                     # content
              c.css(MsgCSS[:reply]).map{|reply_of|
                yield subject, To, (@base.join reply_of['href']), graph    # reply-of reference
                reply_of.remove}

              c.traverse{|n|                                               # hrefize text nodes
                if n.text? && n.to_s.match?(/https?:\/\//)
                  n.add_next_sibling (CGI.unescapeHTML n.to_s).hrefs{|p,o| yield subject, p, o}
                  n.remove
                end}

              yield subject, Content, Webize::HTML.format(c.to_s, @base), graph}

            post.remove
          end}
        @doc.css(MsgCSS[:gunk]).map &:remove                               # sweep gunk nodes

      end
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
end

class WebResource
  module HTML
    MarkupPredicate['http://www.w3.org/1999/xhtml/vocab#role'] = -> roles, env {} # TODO find where are these triples coming from and either shut them off or make a real view if we figure out what they are and deem that useful

    Markup['http://www.w3.org/ns/posix/stat#File'] = -> file, env {
      [({class: :file,
         c: [{_: :a, href: file['uri'], class: :icon, c: Icons['http://www.w3.org/ns/posix/stat#File']},
             {_: :span, class: :name, c: file['uri'].R.basename}]} if file['uri']),
       (HTML.keyval file, env)]}

    MarkupPredicate[Type] = -> types, env {
      types.map{|t|
        t = t.to_s unless t.class == WebResource
        t = t.R env
        {_: :a, href: t.href, c: Icons[t.uri] || t.display_name}.update(Icons[t.uri] ? {class: :icon} : {})}}

    MarkupPredicate[Creator] = MarkupPredicate['http://xmlns.com/foaf/0.1/maker'] = -> creators, env {
      creators.map{|creator|
        if [WebResource, RDF::URI].member? creator.class
          uri = creator.R env
          name = uri.display_name
          color = Digest::SHA2.hexdigest(name)[0..5]
          {_: :a, class: :from, href: uri.href, style: "background-color: ##{color}", c: name}
        else
          markup creator, env
        end}}

    MarkupPredicate[To] = -> recipients, env {
      recipients.map{|r|
        if [WebResource, RDF::URI].member? r.class
          uri = r.R env
          name = uri.display_name
          color = Digest::SHA2.hexdigest(name)[0..5]
          {_: :a, class: :to, href: uri.href, style: "background-color: ##{color}", c: name}
        else
          markup r, env
        end}}

    MarkupPredicate[Abstract] = -> as, env {
      {class: :abstract, c: as.map{|a|[(markup a, env), ' ']}}}

    MarkupPredicate[Schema + 'authToken'] = -> tokens, env {tokens.map{|t| '🪙 '}}

    MarkupPredicate[Schema + 'value'] = -> vs, env {
      vs.map{|v|
        if v.class == RDF::Literal && v.to_s.match?(/^(http|\/)\S+$/)
          v = v.to_s.R env                                             # cast literal to URI (erroneous upstream data)
          if v.uri.match? /\bmp3/
            Markup[Audio][v, env]
          else
            markup v, env
          end
        else
          markup v, env
        end}}

    MarkupPredicate[Title] = -> ts, env {
      ts.map(&:to_s).map(&:strip).uniq.map{|t|
        [CGI.escapeHTML(t), ' ']}}

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
