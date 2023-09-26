module Webize
  module CSS

    Code = Webize.configData 'style/code.css'
    Site = Webize.configData 'style/site.css'

    URL = /url\(['"]*([^\)'"]+)['"]*\)/

  end
end
