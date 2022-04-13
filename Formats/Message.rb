# coding: utf-8
module Webize
  module HTML
    class Reader

      # item/message/post -> RDF
      def scanMessages
        @doc.css("article, .athing, .comment, .entry, .message, [id^='post'], .post, .postCell, .post-container, .post_wrapper, td.subtext, .views-row").map{|post| # posts
          links = post.css('a.linkSelf, a.post_no, a.titlelink, .age > a, .entry-title a, .postNum a, .views-field-title a, .u-url')
          subject = if !links.empty?
                      links[0]['href']                                            # identifier in link to self
                    else
                      post['data-post-no'] || post['id']                          # identifier in node attribute
                    end
          if subject                                                              # subject identifier found
            subject = @base.join subject                                          # resolve subject URI
            graph = ['//', subject.host, subject.path&.sub(/\.html$/, ''),        # construct graph URI
                     '/', subject.fragment].join.R                                # store fragment-URIs in thread container (break out to discrete doc)

            yield subject, Type, (SIOC + 'BoardPost').R, graph                    # RDF type
            post.css('.age, [data-time], [data-utc], [datetime], [unixtime]').map{|date|

              unixtime = date['data-time'] ||
                         date['data-utc'] ||
                         date['unixtime']

              ts = if date['datetime']
                     date['datetime']
                   elsif unixtime
                     Time.at((unixtime).to_i).iso8601
                   elsif date['title']
                     date['title']
                   end

              yield subject, Date, ts, graph if ts}                               # ISO8601 and UNIX (integer since 1970 epoch) timestamp

            post.css(".labelCreated, td.thead > div.normal, .postdate, span.datetime, .time-since").map{|created| # non-ISO8601  timestamp
              if date = Chronic.parse(created['data-content'] || created.inner_text)
                yield subject, Date, date.iso8601, graph
                created.remove
              end}

            post.css('.author, .bigusername, .comment-author, .name, .post_author, .poster, .poster-name, .postername, .username').map{|name|
              yield subject, Creator, name.inner_text, graph }                    # author name

            post.css('a.author, a.bigusername, a.hnuser, a.username, .author > a, .p-author > a, .poster a').map{|a|
              yield subject, Creator, (@base.join a['href']), graph; a.remove }   # author URI

            post.css('.entry-title, .post-subject, .post_title, .subject, .title, .views-field-title').map{|subj|
              yield subject, Title, subj.inner_text, graph }                      # title

            post.css('img').map{|i|
              yield subject, Image, (@base.join i['src']), graph}                 # image

            post.css('a.file-image[href], a.fileThumb[href], a.imgLink[href]').map{|a|
              yield subject, Image, (@base.join a['href']), graph}                # image reference

            post.css('.post_image, .post-image, img.thumb').map{|img|             # image reference on parent
              yield subject, Image, (@base.join img.parent['href']), graph }

            post.css('img.multithumb, img.multithumbfirst').map{|img|             # image reference on parent's parent
              yield subject, Image, (@base.join img.parent.parent['href']), graph }

            post.css('[href$="m4v"], [href$="mp4"], [href$="webm"]').map{|a|      # videos
              yield subject, Video, (@base.join a['href']), graph }

            post.css('.comment-comments').map{|c|                                 # comment count
              if count = c.inner_text.strip.match(/^(\d+) comments$/)
                yield subject, 'https://schema.org/commentCount', count[1], graph
              end}

            post.css(".body, .comment, .content, .e-content, .entry-content, .divMessage, .message, .messageContent, .message-body, .post-body, .postarea, .postbody, [id^='post_message'], .postMessage, .text, .views-field-body, span.sitestr, span.score").map{|msg|
              msg.css('a[class^="ref"], a[onclick*="Reply"], .post-link, .quote_link, .quotelink, .quoteLink, .reply a').map{|reply_of|
                yield subject, To, (@base.join reply_of['href']), graph           # reply-of references
                reply_of.remove}

              msg.traverse{|n|                                                    # references in text content
                if n.text? && n.to_s.match?(/https?:\/\//)
                  n.add_next_sibling (CGI.unescapeHTML n.to_s).hrefs{|p,o| yield subject, p, o}
                  n.remove
                end}

              yield subject, Content, Webize::HTML.format(msg.to_s, @base), graph # message body
              post.remove}                                                        # GC raw post HTML emitted as RDF
          else
            #puts "identifier search failed in:", post if Verbose
          end
        }
        @doc.css('#boardNavMobile, #delform, #absbot, #navtopright, #postForm, #postingForm, #actionsForm, #thread-interactions').map &:remove

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
    MarkupPredicate['http://www.w3.org/1999/xhtml/vocab#role'] = -> roles, env {} # TODO where are these triples coming from?

    MarkupPredicate[Type] = -> types, env {
      types.map{|t|
        t = t.to_s unless t.class == WebResource
        t = t.R env
        {_: :a, href: t.href, c: Icons[t.uri] || t.display_name}.update(Icons[t.uri] ? {class: :icon} : {})}}

    MarkupPredicate[Creator] = MarkupPredicate[To] = MarkupPredicate['http://xmlns.com/foaf/0.1/maker'] = -> creators, env {
      creators.map{|creator|
        if [WebResource, RDF::URI].member? creator.class
          uri = creator.R env
          name = uri.display_name
          color = Digest::SHA2.hexdigest(name)[0..5]
          {_: :a, href: uri.href, style: "background-color: ##{color}", c: name}
        else
          markup creator, env
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

    Markup[Resource] = -> re, env {
      types = re.delete(Type) || []
      im = types.member? SIOC+'InstantMessage'
      titled = re.has_key? Title
      re.delete Date if im

      if uri = re.delete('uri')                                  # unless blank node:
        uri = uri.R env;  id = uri.local_id                      # origin and proxy URIs
        blocked = uri.deny? && !LocalAllow.has_key?(uri.host)    # resource blocked?
        origin_ref = {_: :a, class: :pointer, href: uri,         # origin pointer
                      c: CGI.escapeHTML(uri.path || '')}         # cache pointer
        cache_ref = {_: :a, href: uri.href, id: 'p'+Digest::SHA2.hexdigest(rand.to_s)}
        color = HostColors[uri.host] if HostColors.has_key? uri.host
      end

      p = -> a {                                                 # predicate renderer lambda
        MarkupPredicate[a][re.delete(a),env] if re.has_key? a}

      from = {class: :creator, c: p[Creator]} if re.has_key? Creator
      if re.has_key? To
        color = '#' + Digest::SHA2.hexdigest(re[To][0].R.display_name)[0..5] if re[To].size == 1 && [WebResource, RDF::URI].member?(re[To][0].class)
        text_color = color[3..4].hex > 127 ? :black : :white
        to = {class: :to, c: p[To]}
      end

      date = p[Date]
      link = {class: titled ? :title : nil,c: titled ? p[Title] : :🔗}. # resource pointer
               update(cache_ref || {}).update((titled && color) ? {style: "background-color: #{color}; color: #{text_color || :black}"} : {})

      unless (re[Creator]||[]).find{|a| KillFile.member? a.to_s} # sender killfiled?
        {class: im ? 'post im' : 'post',                         # resource
         c: [(link if titled),                                   # title + resource pointer
             {class: blocked ? 'blocked content' : :content,
              c: [(link unless titled),                          # resource pointer (untitled)
                  p[Abstract],                                   # abstract
                  from,                                          # creator
                  p[Image],                                      # image(s)
                  [Content, SIOC+'richContent'].map{|p|
                    (re.delete(p)||[]).map{|o|markup o,env}},    # body
                  p[Link],                                       # untyped links
                  (HTML.keyval(re,env) unless re.keys.size < 1), # key/val render remaining data
                  to,                                            # receiver
                  date,                                          # timestamp
                 ]}.update(color ? {style: "border-color: #{color}"} : {}),
             origin_ref,                                         # origin pointer
            ]}.update(id ? {id: id} : {})                        # representation identifier
      end}

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
