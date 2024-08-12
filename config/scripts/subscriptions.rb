module Webize
  module Feed

    # mixcloud
    subscribe 'www.mixcloud.com' do |chan|
      "https://api.mixcloud.com/#{chan}/cloudcasts/"
    end

    # soundcloud
    SoundcloudTokens = Webize.configHash 'tokens/soundcloud'

    subscribe 'soundcloud.com' do |chan|

      "https://api-v2.soundcloud.com/stream/users/#{chan}?client_id=#{SoundcloudTokens['client_id']}&limit=20&offset=0&linked_partitioning=1&app_version=#{SoundcloudTokens['version']}&app_locale=en"
    end

    # youtube
    subscribe 'www.youtube.com' do |chan|
      'https://www.youtube.com/feeds/videos.xml?channel_id=' + chan
    end

  end
end
