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
 gunk
 image imageP imagePP
 link
 post
 reply
 title
 video).map{|a| # load user-defined maps
        MsgCSS[a.to_sym] = Webize.configList('metadata/CSS/' + a).join ', '}

      DateAttr = %w(data-time data-timestamp data-utc date datetime time timestamp unixtime data-content title)

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
              childPost.remove if !childPost.css(MsgCSS[:link]).empty? || childPost['id']
            }

            subject = @base.join subject                                   # subject URI
            graph = ['//', subject.host, subject.path].join.R              # graph URI

            yield subject, Type, (SIOC + 'BoardPost').R, graph             # RDF type

            post.css(MsgCSS[:date]).map{|d|                                # ISO8601 and UNIX timestamp
              yield subject, Date, d[DateAttr.find{|a| d.has_attribute? a }] || d.inner_text, graph
              d.remove}

            (authorText = post.css(MsgCSS[:creator])).map{|c|              # author
              yield subject, Creator, c.inner_text, graph }
            (authorURI = post.css(MsgCSS[:creatorHref])).map{|c|
              yield subject, Creator, @base.join(c['href']), graph }
            [authorURI, authorText].map{|a|
              a.map{|c|
                c.remove }}

            post.css(MsgCSS[:title]).map{|subj|
              title = subj.inner_text
              yield subject, Title, title, graph if title && !title.empty? # title
              subj.remove }

            post.css(MsgCSS[:image]).map{|a| yield subject, Image, @base.join(a['href']), graph} # image @href
            post.css(MsgCSS[:imageP]).map{|img|                                                  # image @href on parent node
              yield subject, Image, @base.join(img.parent['href']), graph }
            post.css(MsgCSS[:imagePP]).map{|img|                                                 # image @href on parent-parent node
              yield subject, Image, @base.join(img.parent.parent['href']), graph }

            post.css(MsgCSS[:video]).map{|a| yield subject, Video, @base.join(a['href']), graph} # video

            post.css('.comment-comments').map{|c|                          # comment count
              if count = c.inner_text.strip.match(/^(\d+) comments$/)
                yield subject, 'https://schema.org/commentCount', count[1], graph
              end}

            cs = post.css MsgCSS[:content]                                 # content nodes
            cs.push post if cs.empty?

            cs.map{|c|                                                     # content
              c.css(MsgCSS[:reply]).map{|reply_of|
                yield subject, To, @base.join(reply_of['href']), graph    # reply-of reference
                reply_of.remove}

              c.traverse{|n|                                               # hrefize text nodes
                if n.text? && n.to_s.match?(/https?:\/\//) && n.parent.name != 'a'
                  n.add_next_sibling (CGI.unescapeHTML n.to_s).hrefs{|p,o| yield subject, p, o}
                  n.remove
                end}

              yield subject, Content, Webize::HTML.format(c.to_s, @base), graph
            }
            post.remove
#          else
#            puts "no subject URI found for message: ", post
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
    MarkupPredicate[Link] = -> links, env {
      links.select{|l|[Webize::URI, Webize::Resource, RDF::URI].member? l.class}.
        map{|l| Webize::URI.new l }.select{|l| !l.deny?}.group_by{|l|
        links.size > 8 && l.host && l.host.split('.')[-1] || nil}.map{|tld, links|
        [{class: :container,
          c: [({class: :head, _: :span, c: tld} if tld),
              {class: :body, c: links.group_by{|l|links.size > 25 ? ((l.host||'localhost').split('.')[-2]||' ')[0] : nil}.map{|alpha, links|
                 ['<table><tr>',
                  ({_: :td, class: :head, c: alpha} if alpha),
                  {_: :td, class: :body,
                   c: {_: :table, class: :links,
                       c: links.group_by(&:host).map{|host, paths|
                         h = Webize::Resource '//' + (host || 'localhost'), env
                         {_: :tr,
                          c: [{_: :td, class: :host,
                               c: host ? {_: :a, href: h.href,
                                          c: {_: :img, alt: h.display_host, src: Webize::Resource.new(h.join('/favicon.ico')).env(env).href},
                                          style: "background-color: #{HostColor[host] || '#000'}; color: #fff"} : []},
                              {_: :td, class: :path,
                               c: paths.map{|p|
                                 [{_: :a, href: p.uri, c: p.display_name}, ' ']}}]}}}}, # links
                  '</tr></table>']}}]}, '&nbsp;']}}

    MarkupPredicate[Type] = -> types, env {
      types.map{|t|
        t = Webize::Resource t, env
        {_: :a, href: t.href, c: Icons[t.uri] || t.display_name}.update(Icons[t.uri] ? {class: :icon} : {})}}

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

    MarkupPredicate[Abstract] = -> as, env {
      {class: :abstract, c: as.map{|a|[(markup a, env), ' ']}}}

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

    Markup[BasicResource] = -> re, env {
      env[:last] ||= {}
      p = -> a {MarkupPredicate[a][re[a], env] if re.has_key? a} # predicate renderer
      titled = (re.has_key? Title) && env[:last][Title] != re[Title]
      if uri = re['uri']                                         # unless blank node:
        uri = Webize::Resource.new(uri).env env; id = uri.local_id                      # full URI and fragment identifier
        origin_ref = {_: :a, class: :pointer, href: uri, c: :🔗} # origin pointer
        cache_ref = {_: :a, href: uri.href, id: 'p'+Digest::SHA2.hexdigest(rand.to_s)} # cache pointer
        color = if HostColor.has_key? uri.host
                  HostColor[uri.host]
                elsif uri.deny?
                  env[:gradientR], env[:gradientA], env[:gradientB] = [300, 4, 8]
                  :red
                end
      end
      from = p[Creator] # unless env[:last][Creator] == re[Creator]
      if re.has_key? To
        if re[To].size == 1 && [Webize::URI, Webize::Resource, RDF::URI].member?(re[To][0].class)
          color = '#' + Digest::SHA2.hexdigest(Webize::URI.new(re[To][0]).display_name)[0..5]
        end
        to = p[To]
      end
      date = p[Date]
      link = {class: :title, c: p[Title]}.              # title
               update(cache_ref || {}) if titled
      env[:last] = re
      sz = rand(10) / 3.0
      rest = {}
      re.map{|k,v|
        rest[k] = re[k] unless [Abstract, Content, Creator, Date, From, Link, SIOC + 'richContent', Title, 'uri', To, Type].member? k}
      {class: :post,                                    # resource
       c: [link,                                        # title
           origin_ref,                                  # pointer
           p[Abstract],                                 # abstract
           date,                                        # timestamp
           from,                                        # source
           to,                                          # destination
           [Content, SIOC+'richContent'].map{|p|
             (re[p]||[]).map{|o|markup o,env}},         # body
           p[Link],                                     # untyped links
           (HTML.keyval(rest, env) unless rest.empty?)  # key/val render of remaining data
          ]}.update(id ? {id: id} : {}).update(color ? {style: "background: repeating-linear-gradient(#{env[:gradientR] ||= rand(360)}deg, #{color}, #{color} #{env[:gradientA] ||= rand(16) / 16.0}em, #000 #{env[:gradientA]}em, #000 #{env[:gradientB] ||= env[:gradientA] + rand(16) / 16.0}em); border-color: #{color}"} : {})}

  end
end
