module Webize

  MIME::ReFormat.clear # disable rewriting of HTML

  ReHost = {
    'm.soundcloud.com' => 'soundcloud.com',
    'nitter.net' => 'twitter.com',
    'old.reddit.com' => 'www.reddit.com',
    'twitter.com' => 'nitter.net',
    'www.reddit.com' => 'old.reddit.com',
  }

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
        'www.youtube.com' => :YouTube,
      }

    end
  end
  module JSON
    Triplr = {
      'api.mixcloud.com' => :Mixcloud,
    }
  end

  POSIX::Node::HomePage = 'bookmarks/{home.u,search.🐢}'

  class HTTP::Node

    # site-specific RDF mapping

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

    # read RDF from JSON embedded in Javascript value in HTML
    def JSONembed doc, pattern, &b
      doc.css('script').map{|script|
        script.inner_text.lines.grep(pattern).map{|line|
          Webize::JSON::Reader.new(line.sub(/^[^{]+/,'').chomp.sub(/};.*/,'}'), base_uri: self).scanContent &b}}
    end

    def YoutuBe
      [301, {'Location' => Node(['//www.youtube.com/watch?v=', path[1..-1]].join).href}, []]
    end

    def YouTube doc, &b
      JSONembed doc, /var ytInitial(Data|PlayerResponse) = /i, &b
    end
  end
end
