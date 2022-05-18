# coding: utf-8
module Webize
  module HTML
    class Reader
      Triplr = {
        'apnews.com' => :AP,
        'gitter.im' => :GitterHTML,
        'lobste.rs' => :Lobsters,
        'spinitron.com' => :Spinitron,
        'universalhub.com' => :UHub,
        'www.apnews.com' => :AP,
        'www.google.com' => :GoogleHTML,
        'www.instagram.com' => :InstagramHTML,
        'www.nationalgeographic.com' => :NatGeo,
        'www.nytimes.com' => :NYT,
        'www.nts.live' => :NTS,
        'www.qrz.com' => :QRZ,
        'www.scmp.com' => :Apollo,
        'www.thecrimson.com' => :Apollo,
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
      'www.instagram.com' => :InstagramJSON,
      'www.mixcloud.com' => :Mixcloud,
    }
  end
end
class WebResource
  module HTTP

    CDNhost = /\.(amazonaws|cloudfront|github)\.(com|io|net)$/
    CDNdoc = /(\/|\.(html|jpe?g|p(df|ng)|webp))$/i
    NoGunk  = -> r {r.send r.uri.match?(Gunk) ? :deny : :fetch}

    # strip query from request and response
    NoQuery = -> r {
      if !r.query                         # URL is query-free
        NoGunk[r].yield_self{|s,h,b|      # call origin
          h.keys.map{|k|                  # strip redirected-location query
            if k.downcase == 'location' && h[k].match?(/\?/)
              puts "dropping query from #{h[k]}"
              h[k] = h[k].split('?')[0]
            end
          }
          [s,h,b]}                        # response
      else                                # redirect to no-query location
        puts "dropping query from #{r.uri}"
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
      ps.size > 1 ? [301, {'Location' => ('https://' + ps[-1]).R(r.env).href}, []] : NoGunk[r]}

    GET 'res.cloudinary.com', ImgRehost
    GET 'dynaimage.cdn.cnn.com', GotoBase

    Resizer = -> r {
      if r.parts[0] == 'resizer'
        parts = r.path.split /\/\d+x\d+\/((filter|smart)[^\/]*\/)?/
        parts.size > 1 ? [302, {'Location' => 'https://' + parts[-1]}, []] : NoGunk[r]
      else
        NoGunk[r]
      end}

    %w(bostonglobe-prod.cdn.arcpublishing.com).map{|host|GET host, Resizer}

    # connectivity-check hosts
    GET 'detectportal.firefox.com', -> r {[200, {'Content-Type' => 'text/html'}, ['<meta http-equiv="refresh" content="0;url=https://support.mozilla.org/kb/captive-portal"/>']]}

    # misc
    GET 'www.facebook.com', NoGunk
    GET 'feeds.feedburner.com', -> r {r.parts[0].index('~') ? r.deny : NoGunk[r]}

    GET 'gitter.im', -> r {
      if r.parts[0] == 'api'
        token = r.join('/token').R
        if !r.env.has_key?('x-access-token') && token.node.exist?
          r.env['x-access-token'] = token.node.read
        end
        r.query ? NoGunk[r] : r.cacheResponse
      else
        NoGunk[r]
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
      when /^(dl|images|x?js|maps)$/
        NoGunk[r]
      when 'search'
        r.fetch
      when 'sorry' # denied, switch to DuckduckGo
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
        NoGunk[r]
      end}

    GET 'us.conv.indeed.com', -> r {[301, {'Location' => ['//www.indeed.com/viewjob?jk=', r.query_values['jk']].join.R(r.env).href}, []]}

    GET 'instagram.com', -> r {[301, {'Location' => ['//www.instagram.com', r.path].join.R(r.env).href}, []]}

    GET 'api.mixcloud.com', -> r {
      r.offline? ? r.cacheResponse : r.fetchHTTP(format: 'application/json')}

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
        NoGunk[r]
      end}

    GET 'outline.com', -> r {
      if r.parts.size == 1
        (r.join ['/stat1k/', r.parts[0], '.html'].join).R(r.env).fetch
      else
        NoGunk[r]
      end}

    GET 'old.reddit.com', -> r {
      r.fetch.yield_self{|status,head,body|
        if status.to_s.match? /^30/
          [status, head, body]
        else # find page pointers in <body> (old UI) as they're missing in HEAD and <head> (old and main UI) and <body> (main UI)
          links = []
          body[0].scan(/href="([^"]+after=[^"]+)/){|link|links << CGI.unescapeHTML(link[0]).R} if body.class == Array && body[0].class == String # find page references
          [302, {'Location' => (links.empty? ? r.href : links.sort_by{|r|r.query_values['count'].to_i}[-1]).to_s.sub('old','www')}, []] # goto link with highest count
        end}}

    GET 'www.reddit.com', -> r {
      ps = r.parts
      r.env[:group] = Title unless ps[-1] == 'new'
      r.env[:links][:prev] = ['//old.reddit.com', (r.path || '/').sub('.rss',''), '?',r.query].join.R r.env # previous-page pointer
      if !ps[0] || %w(comments r u user).member?(ps[0])
        r.path += '.rss' unless r.offline? || !r.path || r.path.index('.rss')
        NoGunk[r]
      elsif %w(favicon.ico gallery wiki video).member? ps[0]
        NoGunk[r]
      else
        r.deny
      end}

    GotoReddit =  -> r {[302, {'Location' => ('//www.reddit.com' + r.path).R(r.env).href}, []]}
    GET 'teddit.net', GotoReddit
    GET 'np.reddit.com', GotoReddit

    GET 's4.reutersmedia.net', -> r {
      args = r.query_values || {}
      if args.has_key? 'w'
        args.delete 'w'
        [301, {'Location' => (qs args)}, []]
      else
        NoGunk[r]
      end}

    GET 'cdn.shortpixel.ai', ImgRehost

    GET 'soundcloud.com', -> r {
      if !r.path || r.path == '/'
        barrier = Async::Barrier.new
	semaphore = Async::Semaphore.new(16, parent: barrier)
        client_id = 'qpb3ePPttWrQPwdAw7dRY7sxJCe6Z8pj'
        version = 1650464268
        Webize.configList('subscriptions/soundcloud').map{|chan|
          semaphore.async do
            print "🔊"
            "https://api-v2.soundcloud.com/stream/users/#{chan}?client_id=#{client_id}&limit=20&offset=0&linked_partitioning=1&app_version=#{version}&app_locale=en".R(r.env).fetchHTTP thru: false
          end}
        barrier.wait
        r.saveRDF.graphResponse
      else
       NoGunk[r]
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
          r.cacheResponse
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
        NoGunk[r]
      end}

    GET 'twitter.com', Twitter
    GET 'mobile.twitter.com', -> r {[301, {'Location' => ['//twitter.com', r.path, '?', r.query].join.R(r.env).href}, []]}
    GET 'www.twitter.com', Twitter

    GET 'radar.weather.gov', -> r {
      r.env[:cache] = r if r.file?
      r.fetchHTTP}

    GET 'wiki.c2.com', -> r {
      proxyURL = ['https://proxy.c2.com/wiki/remodel/pages/', r.env['QUERY_STRING']].join.R r.env
      proxyURL.fetchHTTP format: 'application/json'}

    GET 's.yimg.com', ImgRehost

    GET 'news.ycombinator.com', -> r {
      r.env[:group] ||= 'to'
      r.env[:order] ||= 'asc'
      r.env[:sort] ||= 'date'
      r.env[:view] ||= 'table'
      NoGunk[r]}

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
          NoGunk[r]
        end
      else
        r.deny
      end}
  end

  def Apollo doc, &b
    JSONembed doc, /window[^{]+Apollo[^{]+{/i, &b
  end

  def AP doc
    doc.css('script').map{|script|
      script.inner_text.scan(/window\['[-a-z]+'\] = ([^\n]+)/){|data| # find the JSON
        data = data[0]
        data = data[0..-2] if data[-1] == ';'
        Webize::JSON::Reader.new(data, base_uri: self).scanContent do |s,p,o| # call JSON triplr
          if p == 'gcsBaseUrl' # bind image URL
            p = Image
            o += '2000.jpeg'
          end
          yield s,p,o
        end}}
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
            puts ['🎫 ', host, token].join ' '
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

  def InstagramHTML doc, &b
    objvar = /^window._sharedData = /
    doc.css('script').map{|script|
      if script.inner_text.match? objvar
        InstagramJSON ::JSON.parse(script.inner_text.sub(objvar, '')[0..-2]), &b
      end}
  end

  def InstagramJSON tree, &b
    Webize::JSON.scan(tree){|h|
      if tl = h['edge_owner_to_timeline_media']
        end_cursor = tl['page_info']['end_cursor'] rescue nil
        uid = tl["edges"][0]["node"]["owner"]["id"] rescue nil
        env[:links][:prev] ||= 'https://www.instagram.com/graphql/query/' + HTTP.qs({query_hash: :e769aa130647d2354c40ea6a439bfc08, variables: {id: uid, first: 12, after: end_cursor}.to_json}) if uid && end_cursor
      end
      if h['shortcode']
        s = graph = ['https://www.instagram.com/p/', h['shortcode'], '/'].join.R
        yield s, Type, Post.R, graph
        yield s, Image, h['display_url'].R, graph if h['display_url']
        if owner = h['owner']
          yield s, Creator, ('https://www.instagram.com/' + owner['username']).R, graph if owner['username']
          yield s, To, 'https://www.instagram.com/'.R, graph
        end
        if time = h['taken_at_timestamp']
          yield s, Date, Time.at(time).iso8601, graph
        end
        if text = h['edge_media_to_caption']['edges'][0]['node']['text']
          yield s, Content, Webize::HTML.format(CGI.escapeHTML(text).split(' ').map{|t|
                                                  if match = (t.match /^@([a-zA-Z0-9._]+)(.*)/)
                                                    "<a class='uri' href='https://www.instagram.com/#{match[1]}'>#{match[1]}</a>#{match[2]}"
                                                  else
                                                    t
                                                  end}.join(' '), self), graph
        end rescue nil
      end}
  end

  def Lobsters doc
    doc.css('.h-entry').map{|entry|
      avatar, author, archive, post = entry.css('.byline a')
      post = archive unless post
      subject = join post['href']
      yield subject, Type, Post.R
      yield subject, Creator, (join author['href'])
      yield subject, Creator, author.inner_text
      yield subject, Image, (join avatar.css('img')[0]['src'])
      yield subject, Date, Time.parse(entry.css('.byline > span[title]')[0]['title']).iso8601
      entry.css('.link > a').map{|link|
        yield subject, Link, (join link['href'])
        yield subject, Title, link.inner_text}
      entry.css('.tags > a').map{|tag|
        yield subject, To, (join tag['href'])
        yield subject, Abstract, tag['title']}

      entry.remove }

    doc.css('div.comment[id]').map{|comment|
      post_id, avatar, author, post_link = comment.css('.byline > a')
      if post_link
        subject = (join post_link['href']).R
        graph = subject.join [subject.basename, subject.fragment].join '.'
        yield subject, Type, Post.R, graph
        yield subject, To, (join subject.path), graph
        yield subject, Creator, (join author['href']), graph
        yield subject, Creator, author.inner_text, graph
        yield subject, Image, (join avatar.css('img')[0]['src']), graph
        yield subject, Date, Time.parse(comment.css('.byline > span[title]')[0]['title']).iso8601, graph
        yield subject, Content, (Webize::HTML.format comment.css('.comment_text')[0], self), graph
      end
      comment.remove }
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

  def NatGeo doc, &b
    JSONembed doc, /window[^{]+NatGeo[^{]+{/i, &b
  end

  def NYT doc, &b
    JSONembed doc, /^window.__preload/, &b
  end

  def NTS doc, &b
    JSONembed doc, /window._REACT_STATE/, &b
    doc.css('button[data-src]').map{|button|
      yield self, Link, button['data-src'].R}
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
