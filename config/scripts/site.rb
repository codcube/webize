module Webize

  CDN_host = 'x'
  CDN_port = 8000

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
  module JSON
    Triplr = {
      'api.mixcloud.com' => :Mixcloud,
    }
  end

  class HTTP::Node

    # site-specific RDF mapping

    def Mixcloud tree, &b
      if data = tree['data']
        data.map{|mix|
          graph = subject = RDF::URI(mix['url'])
          date = mix['created_time']
          yield subject, Type, RDF::URI(Post), graph
          yield subject, Title, mix['name'], graph
          yield subject, Date, date, graph
          yield subject, Creator, mix['user']['name'], graph
          yield subject, To, RDF::URI(mix['user']['url']), graph
          mix['pictures'].map{|_,i|
            yield subject, Image, RDF::URI(i), graph if i.match? /1024x1024/}
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

  end
end
