# coding: utf-8
module Webize
  module HTML
    class Reader
      Triplr = {
        'www.google.com' => :GoogleHTML,
        'www.qrz.com' => :QRZ,
        'www.youtube.com' => :YouTube,
      }

    end
  end
  module JSON
    Triplr = {
      'api.imgur.com' => :Imgur,
      'api.mixcloud.com' => :Mixcloud,
      'proxy.c2.com' => :C2,
    }
  end
end
class WebResource

  module HTTP

    ## subscriptions

    Subscriptions['www.mixcloud.com'] = Webize.configList('subscriptions/mixcloud').map{|c|
      "https://api.mixcloud.com/#{c}/cloudcasts/"}

    SC = {client_id: 'nBNZK2jas9ofvx4mqT6KYcUoDFeOdlRn', version: 1680773289}

    Subscriptions['soundcloud.com'] = Webize.configList('subscriptions/soundcloud').map{|chan|
      "https://api-v2.soundcloud.com/stream/users/#{chan}?client_id=#{SC[:client_id]}&limit=20&offset=0&linked_partitioning=1&app_version=#{SC[:version]}&app_locale=en"}

    Subscriptions['www.youtube.com'] = Webize.configList('subscriptions/youtube').map{|c|
      'https://www.youtube.com/feeds/videos.xml?channel_id=' + c}

    ## GET handlers

    GET 'google.com', -> r {[301, {'Location' => ['//www.google.com', r.path, '?', r.query].join.R(r.env).href}, []]}
    GET 'www.google.com', -> r {
      case r.parts[0]
      when 'amp'
        r.path.index('/amp/s/') == 0 ? [301, {'Location' => ('https://' + r.path[7..-1]).R(r.env).href}, []] : r.deny
      when 'imgres'
        [301, {'Location' => r.query_values['imgurl'].R(r.env).href}, []]
      when /^(dl|images|x?js|maps|search)$/
        r.fetch
      when 'sorry' # denied, goto DDG
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

    # read page pointers visible in HTML <body> (old UI) as they're missing in HTTP HEAD and HTML <head> (old/new UI) and HTML <body> (new UI)
    GET 'old.reddit.com', -> r {
      r.fetch.yield_self{|status,head,body|
        if status.to_s.match? /^30/
          [status, head, body]
        else
          links = []
          if body.class == Array && body[0].class == String
            body[0].scan(/href="([^"]+after=[^"]+)/){|link| # page pointers in <body>
              links << CGI.unescapeHTML(link[0]).R}
          end
          [302, {'Location' => (links.empty? ? r.href : links.sort_by{|r|r.query_values['count'].to_i}[-1]).to_s.sub('old','www')}, []] # redirect to page with highest count
        end}}

    GET 'www.reddit.com', -> r {
      ps = r.parts
      r.env[:links][:prev] = ['//old.reddit.com', (r.path || '/').sub('.rss',''), '?',r.query].join.R r.env # previous-page pointer
      if !ps[0] || %w(comments r u user).member?(ps[0])
        r.path += '.rss' unless r.offline? || !r.path || r.path.index('.rss') # add .rss to URL to request preferred content-type
        r.env.delete 'HTTP_REFERER'
        r.fetch
      elsif %w(favicon.ico gallery wiki video).member? ps[0]
        r.fetch
      else
        r.deny
     end}

    GET 'wiki.c2.com', -> r {['https://proxy.c2.com/wiki/remodel/pages/', r.env['QUERY_STRING']].join.R(r.env).fetchHTTP}

    GET 'www.youtube.com', -> r {
      r.env[:searchbase] = '/results'
      r.env[:searchterm] = 'search_query'
      path = r.parts[0]
      qs = r.query_values || {}
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
      end}

    GET 'm.youtube.com',     -> r {[301, {'Location' => ['//www.youtube.com',  r.path,  '?', r.query].join.R(r.env).href}, []]}
    GET 'music.youtube.com', -> r {[301, {'Location' => ['//www.youtube.com',  r.path,  '?', r.query].join.R(r.env).href}, []]}
    GET 'youtube.com',       -> r {[301, {'Location' => ['//www.youtube.com',  r.path,  '?', r.query].join.R(r.env).href}, []]}
    GET 'youtu.be', -> r {[301, {'Location' => ['//www.youtube.com/watch?v=', r.path[1..-1]].join.R(r.env).href}, []]}

    # site-specific RDF mapping methods for HTML and JSON

    def C2 tree, &b
      yield self, Date, tree['date']
      yield self, Content, (Webize::HTML.format tree['text'].hrefs, self)
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
        data.map{|mix|
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
          end}
      else
        puts "no data in #{uri}"
      end
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

    def YouTube doc, &b
      JSONembed doc, /var ytInitial(Data|PlayerResponse) = /i, &b
    end
  end
end
