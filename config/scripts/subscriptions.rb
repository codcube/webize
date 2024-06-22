module Webize
  module Feed

    # mixcloud
    Subscriptions['www.mixcloud.com'] = Webize.configList('subscriptions/mixcloud').map{|c|

      "https://api.mixcloud.com/#{c}/cloudcasts/"}

    # soundcloud
    SoundcloudTokens = Webize.configHash 'tokens/soundcloud'

    Subscriptions['soundcloud.com'] = Webize.configList('subscriptions/soundcloud').map{|chan|

      "https://api-v2.soundcloud.com/stream/users/#{chan}?client_id=#{SoundcloudTokens['client_id']}&limit=20&offset=0&linked_partitioning=1&app_version=#{SoundcloudTokens['version']}&app_locale=en"}

    # youtube
    Subscriptions['www.youtube.com'] = Webize.configList('subscriptions/youtube').map{|c|

      'https://www.youtube.com/feeds/videos.xml?channel_id=' + c}

  end
end
