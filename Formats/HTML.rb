# coding: utf-8
%w(read write).map{|rw|
  require_relative "HTML.#{rw}.rb"}

module Webize

  module CSS

    Code = Webize.configData 'style/code.css'
    Site = Webize.configData 'style/site.css'
    URL = /url\(['"]*([^\)'"]+)['"]*\)/

  end

  module HTML

    FeedIcon = Webize.configData 'style/icons/feed.svg'
    HostColor = Webize.configHash 'style/color/host'
    Icons = Webize.configHash 'style/icons/map'
    ReHost = Webize.configHash 'hosts/UI'
    SiteFont = Webize.configData 'style/fonts/hack.woff2'
    SiteIcon = Webize.configData 'style/icons/favicon.ico'
    StatusColor = Webize.configHash 'style/color/status'
    StatusColor.keys.map{|s|
      StatusColor[s.to_i] = StatusColor[s]}
    StripTags = /<\/?(noscript|wbr)[^>]*>/i
    QuotePrefix = /^\s*&gt;\s*/

  end

end
