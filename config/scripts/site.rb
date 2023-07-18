# coding: utf-8
module Webize
  module Feed

    # subscriptions

    Subscriptions['www.mixcloud.com'] = Webize.configList('subscriptions/mixcloud').map{|c|
      "https://api.mixcloud.com/#{c}/cloudcasts/"}

    SoundcloudTokens = Webize.configHash 'tokens/soundcloud'
    Subscriptions['soundcloud.com'] = Webize.configList('subscriptions/soundcloud').map{|chan|
      "https://api-v2.soundcloud.com/stream/users/#{chan}?client_id=#{SoundcloudTokens['client_id']}&limit=20&offset=0&linked_partitioning=1&app_version=#{SoundcloudTokens['version']}&app_locale=en"}

    Subscriptions['www.youtube.com'] = Webize.configList('subscriptions/youtube').map{|c|
      'https://www.youtube.com/feeds/videos.xml?channel_id=' + c}

  end
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
  class HTTP::Resource

    # site-specific RDF mapping

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
            yield subject, Abstract, tag['name'], graph}}
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

    # read RDF from JSON embedded in Javascript value in HTML
    def JSONembed doc, pattern, &b
      doc.css('script').map{|script|
        script.inner_text.lines.grep(pattern).map{|line|
          Webize::JSON::Reader.new(line.sub(/^[^{]+/,'').chomp.sub(/};.*/,'}'), base_uri: self).scanContent &b}}
    end

    def YouTube doc, &b
      JSONembed doc, /var ytInitial(Data|PlayerResponse) = /i, &b
    end
  end
end
