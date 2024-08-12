module Webize
  module Feed

    # mixcloud
    subscribe 'www.mixcloud.com' do |c|
      "https://api.mixcloud.com/#{c}/cloudcasts/"
    end

    # soundcloud
    SoundcloudTokens = Webize.configHash 'tokens/soundcloud'

    subscribe 'soundcloud.com' do |chan|

      "https://api-v2.soundcloud.com/stream/users/#{chan}?client_id=#{SoundcloudTokens['client_id']}&limit=20&offset=0&linked_partitioning=1&app_version=#{SoundcloudTokens['version']}&app_locale=en"
    end

    # youtube
    subscribe 'www.youtube.com' do |c|
      'https://www.youtube.com/feeds/videos.xml?channel_id=' + c
    end

  end
end
