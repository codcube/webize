module Webize
  module Feed

    # soundcloud
    SoundcloudTokens = Webize.configHash 'tokens/soundcloud'

    subscribe 'soundcloud.com' do |chan|

      "https://api-v2.soundcloud.com/stream/users/#{chan}?client_id=#{SoundcloudTokens['client_id']}&limit=20&offset=0&linked_partitioning=1&app_version=#{SoundcloudTokens['version']}&app_locale=en"
    end

  end
end
