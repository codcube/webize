# coding: utf-8
module Webize
  module HTML
    class Reader
      Triplr = {
        'gitter.im' => :GitterHTML,
        'spinitron.com' => :Spinitron,
        'universalhub.com' => :UHub,
        'www.google.com' => :GoogleHTML,
        'www.qrz.com' => :QRZ,
        'www.universalhub.com' => :UHub,
        'www.youtube.com' => :YouTube,
      }

    end
  end
  module JSON
    Triplr = {
      'api.imgur.com' => :Imgur,
      'api.mixcloud.com' => :MixcloudAPI,
      'gitter.im' => :GitterJSON,
      'proxy.c2.com' => :C2,
      'www.mixcloud.com' => :Mixcloud,
    }
  end
end
class WebResource

  NoSummary = [Image,                      # don't summarize these resource-types
               Schema + 'ItemList',
               Schema + 'Readme',
               SIOC + 'MicroPost'].map &:R

  module HTTP

    CDNhost = /\.(amazon(aws)?|apple|cloud(inary|flare|front)|discord(app)?|f(acebook|bcdn)|g(it(hu|la)b|oogle)(usercontent)?|medium|substack|tumblr)\.(com|io|net)$/
    CDNdoc = /(\/|\.(html|jpe?g|mp4|p(df|ng)|webp))$/i

    NoQuery = -> r { # strip query from request and response (redirect location) URIs
      if !r.query                         # URL is query-free
        r.fetch.yield_self{|s,h,b|        # call origin
          h.keys.map{|k|                  # strip redirected-location query
            if k.downcase == 'location' && h[k].match?(/\?/)
              Console.logger.info "dropping query from #{h[k]}"
              h[k] = h[k].split('?')[0]
            end
          }
          [s,h,b]}                        # response
      else                                # redirect to no-query location
        Console.logger.info "dropping query from #{r.uri}"
        [302, {'Location' => ['//', r.host, r.path].join.R(r.env).href}, []]
      end}

    # shortURL hosts
    Webize.configList('hosts/shorturl').map{|h| GET h, NoQuery}

    GET 'bos.gl', -> r {r.scheme = 'http'; r.fetch} # hangs on HTTPS, use HTTP

    # URL-in-URL hosts with no origin roundtrip
    GotoBase = -> r {[301, {'Location' => (CGI.unescape r.basename)}, []]}

    GotoURL = -> r {
      q = r.query_values || {}
      dest = q['url'] || q['u'] || q['q']
      dest ? [301, {'Location' => dest.R(r.env).href}, []] : r.notfound}

    Webize.configList('hosts/url').map{|h| GET h, GotoURL}

    GET 'urldefense.com', -> r {[302, {'Location' => r.path.split('__')[1].R(r.env).href}, []]}

    # image-specific URL-in-URL hosts
    ImgRehost = -> r {
      ps = r.path.split /https?:\/+/
      ps.size > 1 ? [301, {'Location' => ('https://' + ps[-1]).R(r.env).href}, []] : r.fetch}

    GET 'res.cloudinary.com', ImgRehost
    GET 'dynaimage.cdn.cnn.com', GotoBase

    Resizer = -> r {
      if r.parts[0] == 'resizer'
        parts = r.path.split /\/\d+x\d+\/((filter|smart)[^\/]*\/)?/
        parts.size > 1 ? [302, {'Location' => 'https://' + parts[-1]}, []] : r.fetch
      else
        r.fetch
      end}

    %w(bostonglobe-prod.cdn.arcpublishing.com).map{|host|GET host, Resizer}

    GET 'feeds.feedburner.com', -> r {r.parts[0].index('~') ? r.deny : r.fetch}

    GET 'gitter.im', -> r {
      if r.parts[0] == 'api'
        token = r.join('/token').R
        if !r.env.has_key?('x-access-token') && token.node.exist?
          r.env['x-access-token'] = token.node.read
        end
        r.query ? r.fetch : r.fetchLocal
      else
        r.fetch
      end}

    GotoAdURL =  -> r {
      if url = (r.query_values || {})['adurl']
        dest = url.R
        dest.query = '' unless url.match? /dest_url/
        [301, {'Location' => dest}, []]
      else
        r.deny
      end}

    GET 'googleads.g.doubleclick.net', GotoAdURL
    GET 'www.googleadservices.com', GotoAdURL
    GET 'google.com', -> r {[301, {'Location' => ['//www.google.com', r.path, '?', r.query].join.R(r.env).href}, []]}

    GET 'www.google.com', -> r {
      case r.parts[0]
      when 'amp'
        r.path.index('/amp/s/') == 0 ? [301, {'Location' => ('https://' + r.path[7..-1]).R(r.env).href}, []] : r.deny
      when 'imgres'
        [301, {'Location' => r.query_values['imgurl'].R(r.env).href}, []]
      when /^(dl|images|x?js|maps|search)$/
        r.fetch
      when 'sorry' # denied by antibot, goto DDG
        q = r.query_values['continue'].R.query_values['q']
        [302, {'Location' => 'https://duckduckgo.com/' + HTTP.qs({q: q})}, []]
      when 'url'
        GotoURL[r]
      else
        r.deny
      end}

    GET 'imgur.com', -> r {
      p = r.parts
      case p[0]
      when /^(a|gallery)$/
        [302, {'Location' => "https://api.imgur.com/post/v1/albums/#{p[1]}?client_id=546c25a59c58ad7&include=media%2Cadconfig%2Caccount".R(r.env).href}, []]
      else
        r.fetch
      end}

    GET 'us.conv.indeed.com', -> r {[301, {'Location' => ['//www.indeed.com/viewjob?jk=', r.query_values['jk']].join.R(r.env).href}, []]}

    GET 'api.mixcloud.com', -> r {
      r.offline? ? r.fetchLocal : r.fetchHTTP(format: 'application/json')}

    GET 'mixcloud.com', -> r {[301, {'Location' => ['//www.mixcloud.com', r.path].join.R(r.env).href}, []]}

    GET 'www.mixcloud.com', -> r {
      if !r.path || r.path == '/'
        barrier = Async::Barrier.new
	semaphore = Async::Semaphore.new(16, parent: barrier)
        Webize.configList('subscriptions/mixcloud').map{|chan|
          semaphore.async do
            print "🔊"
            "https://api.mixcloud.com/#{chan}/cloudcasts/".R(r.env).fetchHTTP format: 'application/json', thru: false
          end}
        barrier.wait
        r.saveRDF.graphResponse
      else
        r.env[:feeds].push "https://api.mixcloud.com/#{r.parts[0]}/cloudcasts/"
        r.fetch
      end}

    GET 'old.reddit.com', -> r { # use this host to read page pointers visible in <body> (oldUI) as they're missing in HEAD and <head> (oldUI/newUI) and <body> (newUI)
      r.fetch.yield_self{|status,head,body|
        if status.to_s.match? /^30/
          [status, head, body]
        else
          links = []
          if body.class == Array && body[0].class == String # find page pointers in <body>
            body[0].scan(/href="([^"]+after=[^"]+)/){|link|
              links << CGI.unescapeHTML(link[0]).R}
          end
          [302, {'Location' => (links.empty? ? r.href : links.sort_by{|r|r.query_values['count'].to_i}[-1]).to_s.sub('old','www')}, []] # redirect to page with highest count
        end}}

    GET 'www.reddit.com', -> r {
      ps = r.parts
      r.env[:group] = Title unless ps[-1] == 'new'
      r.env[:links][:prev] = ['//old.reddit.com', (r.path || '/').sub('.rss',''), '?',r.query].join.R r.env # previous-page pointer
      if !ps[0] || %w(comments r u user).member?(ps[0])
        r.path += '.rss' unless r.offline? || !r.path || r.path.index('.rss')
        r.fetch
      elsif %w(favicon.ico gallery wiki video).member? ps[0]
        r.fetch
      else
        r.deny
      end}

    GET 's4.reutersmedia.net', -> r {
      args = r.query_values || {}
      if args.has_key? 'w'
        args.delete 'w'
        [301, {'Location' => (qs args)}, []]
      else
        r.fetch
      end}

    GET 'cdn.shortpixel.ai', ImgRehost

    GET 'soundcloud.com', -> r {
      if !r.path || r.path == '/'
        barrier = Async::Barrier.new
	semaphore = Async::Semaphore.new(16, parent: barrier)
        client_id = 'cvRAZnbmwcaau0MyfJTGwtUjhQNvQlio'
        version = 1655977444
        Webize.configList('subscriptions/soundcloud').map{|chan|
          semaphore.async do
            print "🔊"
            "https://api-v2.soundcloud.com/stream/users/#{chan}?client_id=#{client_id}&limit=20&offset=0&linked_partitioning=1&app_version=#{version}&app_locale=en".R(r.env).fetchHTTP thru: false
          end}
        barrier.wait
        r.saveRDF.graphResponse
      else
        r.fetch
      end}

    GET 'go.theregister.com', -> r {
      if r.parts[0] == 'feed'
        [301, {'Location' => 'https://' + r.path[6..-1]}, []]
      else
        r.deny
      end}

    Twitter = -> r {
      parts = r.parts
      qs = r.query_values || {}
      cursor = qs.has_key?('cursor') ? ('&cursor=' + qs['cursor']) : ''
      users = Webize.configList 'subscriptions/twitter'
      notusers = %w(favicon.ico manifest.json push_service_worker.js search sw.js users)

      if r.env['HTTP_COOKIE'] # auth headers
        attrs = {}
        r.env['HTTP_COOKIE'].split(';').map{|attr|
          k, v = attr.split('=').map &:strip
          attrs[k] = v}
        r.env['authorization'] ||= 'Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
        r.env['x-csrf-token'] ||= attrs['ct0'] if attrs['ct0']
        r.env['x-guest-token'] ||= attrs['gt'] if attrs['gt']
      end

      searchURL = -> q {
        ('https://api.twitter.com/2/search/adaptive.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_ext_alt_text=true&include_quote_count=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweet=true&q='+q+'&tweet_search_mode=live&count=20' + cursor + '&query_source=&pc=1&spelling_corrections=1&ext=mediaStats%2ChighlightedLabel').R(r.env)}

      if !r.path || r.path == '/'                          ## feed
        users.shuffle.each_slice(18){|t| print '🐦'
          searchURL[t.map{|u|'from%3A'+u}.join('%2BOR%2B')].fetchHTTP thru: false}
        r.saveRDF.graphResponse
      elsif parts.size == 1 && !notusers.member?(parts[0]) ## user
        if qs.has_key? 'q'                                  # query user tweet cache
          r.fetchLocal
        elsif qs.has_key? 'ref_src'                         # drop tracking-gunk to prevent URI-filtering
          [301, {'Location' => r.join(r.path).R(r.env).href}, []]
        else                                                # find uid, then fetch tweets and profile
          uid = nil
          uidQuery = "https://twitter.com/i/api/graphql/Vf8si2dfZ1zmah8ePYPjDQ/UserByScreenNameWithoutResults?variables=%7B%22screen_name%22:%22#{parts[0]}%22%2C%22withHighlightedLabel%22:true%7D"
          URI.open(uidQuery, r.headers){|response|
            body = response.read
            if response.meta['content-type'].index 'json'
              json = ::JSON.parse HTTP.decompress({'Content-Encoding' => response.meta['content-encoding']}, body)
              if json['data'].empty?
                r.notfound
              else
                user = json['data']['user']['legacy']
                uid = json['data']['user']['rest_id']
                r.env[:repository] ||= RDF::Repository.new  # profile data RDF
                r.env[:repository] << RDF::Statement.new(r, Abstract.R, ((a = RDF::Literal(Webize::HTML.format user['description'].hrefs, r)).datatype = RDF.HTML; a))
                r.env[:repository] << RDF::Statement.new(r, Date.R, user['created_at'])
                r.env[:repository] << RDF::Statement.new(r, Title.R, user['name'])
                r.env[:repository] << RDF::Statement.new(r, (Schema+'location').R, user['location'])
                %w(profile_banner_url profile_image_url_https).map{|i|
                  if image = user[i]
                    r.env[:repository] << RDF::Statement.new(r, Image.R, image.R)
                  end}
                msgsURL = "https://twitter.com/i/api/graphql/CDDPst9A-AHg6Q0k9-wo7w/UserTweets?variables=%7B%22userId%22%3A%22#{uid}%22%2C%22count%22%3A40%2C%22includePromotedContent%22%3Atrue%2C%22withQuickPromoteEligibilityTweetFields%22%3Atrue%2C%22withSuperFollowsUserFields%22%3Atrue%2C%22withDownvotePerspective%22%3Afalse%2C%22withReactionsMetadata%22%3Afalse%2C%22withReactionsPerspective%22%3Afalse%2C%22withSuperFollowsTweetFields%22%3Atrue%2C%22withVoice%22%3Atrue%2C%22withV2Timeline%22%3Atrue%2C%22__fs_dont_mention_me_view_api_enabled%22%3Afalse%2C%22__fs_interactive_text_enabled%22%3Atrue%2C%22__fs_responsive_web_uc_gql_enabled%22%3Afalse%7D"
                msgsURL.R(r.env).fetch
              end
            else
              [200, response.meta, [body]]
            end} rescue r.notfound
        end
      elsif parts.member?('status') || parts.member?('statuses') ## conversation
        convo = parts.find{|p| p.match? /^\d{8}\d+$/ }
        "https://api.twitter.com/2/timeline/conversation/#{convo}.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&count=20#{cursor}&ext=mediaStats%2CcameraMoment".R(r.env).fetch
      elsif parts[0] == 'hashtag'                          ## hash-tag
        searchURL['%23'+parts[1]].fetch
      elsif parts[0] == 'search'                           ## search
        qs.has_key?('q') ?  searchURL[qs['q']].fetch : r.notfound
      elsif parts[0] == 'users'                            ## user list
        r.env[:repository] ||= RDF::Repository.new
        users.map{|u|
          r.env[:repository] << RDF::Statement.new(r, Link.R, ['//twitter.com/',u].join.R)}
        r.graphResponse
      else
        r.fetch
      end}

    GET 'twitter.com', Twitter
    GET 'mobile.twitter.com', -> r {[301, {'Location' => ['//twitter.com', r.path, '?', r.query].join.R(r.env).href}, []]}
    GET 'www.twitter.com', Twitter

    GET 'wiki.c2.com', -> r {
      proxyURL = ['https://proxy.c2.com/wiki/remodel/pages/', r.env['QUERY_STRING']].join.R r.env
      proxyURL.fetchHTTP format: 'application/json'}

    GET 's.yimg.com', ImgRehost

    GET 'youtu.be', -> r {[301, {'Location' => ['https://www.youtube.com/watch?v=', r.path[1..-1]].join.R(r.env).href}, []]}

    GotoYT = -> r {[301, {'Location' => ['//www.youtube.com', r.path, '?', r.query].join.R(r.env).href}, []]}
    GET 'm.youtube.com', GotoYT
    GET 'youtube.com', GotoYT

    GET 'www.youtube.com', -> r {
      r.env[:searchbase] = '/results'
      r.env[:searchterm] = 'search_query'
      path = r.parts[0]
      qs = r.query_values || {}
      if %w(attribution_link browse_ajax c channel embed feed feeds generate_204 get_video_info guide_ajax heartbeat iframe_api live_chat manifest.json opensearch playlist redirect results s shorts user v watch watch_videos yts).member?(path) || !path
        case path
        when /ajax|embed/
          r.env[:notransform] = true
          r.fetch.yield_self{|s,h,b|
            if h['Content-Type']&.index('html')
              doc = Nokogiri::HTML.parse b[0]
              edited = false
              doc.css('script').map{|s|
                js = /\/\/www.google.com\/js\//
                if s.inner_text.match? js
                  edited = true
                  s.content = s.inner_text.gsub(js,'#')
                end}
              if edited
                b = [doc.to_html]
                h.delete 'Content-Length'
              end
            end
            [s,h,b]}
        when /attribution_link|redirect/
          [301, {'Location' => r.join(qs['q']||qs['u']).R(r.env).href}, []]
        when 'feed'
          barrier = Async::Barrier.new
	  semaphore = Async::Semaphore.new(16, parent: barrier)
          Webize.configList('subscriptions/youtube').map{|chan|
            id = chan.R.parts[-1]
            semaphore.async do
              print "🎞️"
              "https://www.youtube.com/feeds/videos.xml?channel_id=#{id}".R(r.env).fetchHTTP thru: false
            end}
          barrier.wait
          r.saveRDF.graphResponse
        when 'get_video_info'
          if r.query_values['el'] == 'adunit' # TODO ads
            [200, {"Access-Control-Allow-Origin"=>"https://www.youtube.com", "Content-Type"=>"application/x-www-form-urlencoded", "Content-Length"=>"0"}, ['']]
          else
            r.env[:notransform] = true
            r.fetch
          end
        when 'v'
          [301, {'Location' => r.join('/watch?v='+r.parts[1]).R(r.env).href}, []]
        else
          r.fetch
        end
      else
        r.deny
      end}
  end

  def C2 tree, &b
    yield self, Date, tree['date']
    yield self, Content, (Webize::HTML.format tree['text'].hrefs, self)
  end

  def GitterHTML doc
    doc.css('script').map{|script|
      text = script.inner_text
      if text.match? /^window.gitterClientEnv/     # environment JSON
        if token = text.match(/accessToken":"([^"]+)/)
          token = token[1]
          tFile = join('/token').R
          unless tFile.node.exist? && tFile.node.read == token
            tFile.writeFile token                  # save updated client-token
            logger.info ['🎫 ', host, token].join ' '
          end
        end
        if room = text.match(/"id":"([^"]+)/)
          room_id = room[1]                         # room id
          room = ('http://gitter.im/api/v1/rooms/' + room_id + '/').R # room URI
          env[:links][:prev] = room.uri + 'chatMessages?lookups%5B%5D=user&includeThreads=false&limit=31'
          yield room, Schema + 'sameAs', self, room # link room API URI to canonical URI 
          yield room, Type, (SIOC + 'ChatChannel').R
        end
      end}
  end

  def GitterJSON tree, &b
    return if tree.class == Array
    return unless items = tree['items']
    items.map{|item|
      id = item['id']                              # message identifier
      room_id = parts[3]                           # room identifier
      room = ('http://gitter.im/api/v1/rooms/'  + room_id + '/').R # room URI
      env[:links][:prev] ||= room.uri + 'chatMessages?lookups%5B%5D=user&includeThreads=false&beforeId=' + id + '&limit=31'
      date = item['sent']
      uid = item['fromUser']
      user = tree['lookups']['users'][uid]
      graph = ['/' + date.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), 'gitter', user['username'], id].join('.').R # graph on timeline
      subject = 'http://gitter.im' + path + '?at=' + id # subject URI
      yield subject, Date, date, graph
      yield subject, Type, (SIOC + 'MicroPost').R, graph
      yield subject, Creator, join(user['url']), graph
      yield subject, Creator, user['displayName'], graph
      yield subject, To, room, graph
      if image = user['avatarUrl']
        yield subject, Image, join(image), graph
      end
      yield subject, Content, (Webize::HTML.format item['html'], self), graph
    }
  end

  def GoogleHTML doc
    doc.css('div.g').map{|g|
      if r = g.css('a[href]')[0]
        subject = r['href'].R
        if subject.host
          if title = r.css('h3')[0]
            yield subject, Type, (Schema+'SearchResult').R
            yield subject, Title, title.inner_text
            yield subject, Content, Webize::HTML.format(g.inner_html, self)
          end
        end
      end
      g.remove}
    if pagenext = doc.css('#pnnext')[0]
      env[:links][:next] ||= join pagenext['href']
    end
    doc.css('#botstuff, #bottomads, #footcnt, #rhs, #searchform, svg, #tads, #taw, [role="navigation"]').map &:remove
  end

  def Imgur tree, &b
    tree['media'].map{|i|
      url = i['url'].R
      yield self, File.extname(url.path) == '.mp4' ? Video : Image, url}
  end

  def Mixcloud tree, &b
    if data = tree['data']
      if user = data['user']
        if username = user['username']
          if uploads = user['uploads']
            if edges = uploads['edges']
              edges.map{|edge|
                mix = edge['node']
                slug = mix['slug']
                subject = graph = ('https://www.mixcloud.com/' + username + '/' + slug).R
                yield subject, Title, mix['name'], graph
                yield subject, Date, mix['publishDate'], graph
                if duration = mix['audioLength']
                  yield subject, Schema+'duration', duration, graph
                end
                yield subject, Image, ('https://thumbnailer.mixcloud.com/unsafe/1280x1280/' + mix['picture']['urlRoot']).R, graph
                if audio = mix['previewUrl']
                  yield subject, Audio, audio.R, graph
                end
              }
            end
          end
        end
      end
    end
  end

  def MixcloudAPI tree, &b
    yield self, Title, tree['name']
    tree['data'].map{|mix|
      graph = subject = mix['url'].R
      date = mix['created_time']
      unless env.has_key?('HTTP_IF_MODIFIED_SINCE') && date < Time.httpdate(env['HTTP_IF_MODIFIED_SINCE']).iso8601
        yield subject, Type, Post.R, graph
        yield subject, Title, mix['name'], graph
        yield subject, Date, date, graph
        yield subject, Creator, mix['user']['name'], graph
        yield subject, To, mix['user']['url'].R, graph
        mix['pictures'].map{|_,i|
          yield subject, Image, i.R, graph if i.match? /1024x1024/}
        if duration = mix['audio_length']
          yield subject, Schema+'duration', duration, graph
        end
        mix['tags'].map{|tag|
          yield subject, Abstract, tag['name'], graph}
      end
    }
    if pages = tree['paging']
      env[:links][:next] = pages['next'] if pages['next']
      env[:links][:prev] = pages['previous'] if pages['previous']
    end
  end

  def QRZ doc, &b
    doc.css('script').map{|script|
      script.inner_text.scan(%r(biodata'\).html\(\s*Base64.decode\("([^"]+))xi){|data|
        yield self, Content, Base64.decode64(data[0]).encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ')}}
  end

  def Spinitron doc
    if show = doc.css('.show-title > a')[0]
      show_name = show.inner_text
      show_url = join show['href']
      station = show_url.R.parts[0]
    end

    if dj = doc.css('.dj-name > a')[0]
      dj_name = dj.inner_text
      dj_url = join dj['href']
    end

    if timeslot = doc.css('.timeslot')[0]
      day = timeslot.inner_text.split(' ')[0..2].join(' ') + ' '
    end

    doc.css('.spin-item').map{|spin|
      spintime = spin.css('.spin-time > a')[0]
      date = Chronic.parse(day + spintime.inner_text).iso8601
      subject = join spintime['href']
      graph = ['/' + date.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), station, show_name.split(' ')].join('.').R # graph URI
      data = JSON.parse spin['data-spin']
      yield subject, Type, Post.R, graph
      yield subject, Date, date, graph
      yield subject, Creator, dj_url, graph
      yield subject, Creator, dj_name, graph
      yield subject, To, show_url, graph
      yield subject, To, show_name, graph
      yield subject, Schema+'Artist', data['a'], graph
      yield subject, Schema+'Song', data['s'], graph
      yield subject, Schema+'Release', data['r'], graph
      if year = spin.css('.released')[0]
        yield subject, Schema+'Year', year.inner_text, graph
      end
      spin.css('img').map{|img| yield subject, Image, img['src'].R, graph }
      if note = spin.css('.note')[0]
        yield subject, Content, note.inner_html
      end
      spin.remove }
  end

  def UHub doc
    doc.css('.pager-next > a[href]').map{|n|     env[:links][:next] ||= (join n['href'])}
    doc.css('.pager-previous > a[href]').map{|p| env[:links][:prev] ||= (join p['href'])}
    doc.css('.views-field-created').map{|c|
      date, time = c.css('.field-content')[0].inner_text.split '-'
      m, d, y = date.strip.split '/'
      time ||= '00:00'
      time, ampm = time.strip.split /\s/
      hour, min = time.split(':').map &:to_i
      hour += 12 if ampm == 'pm' && hour != 12
      c.add_next_sibling "<time datetime='20#{y}-#{m}-#{d}T#{hour}:#{min}:00Z'>"
      c.remove
    }
  end

  def YouTube doc, &b
    JSONembed doc, /var ytInitial(Data|PlayerResponse) = /i, &b
  end

end
