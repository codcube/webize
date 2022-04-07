#require 'crass'
module Webize
  module CSS

    def self.clean str
      str.gsub(/@font-face\s*{[^}]+}/, '').gsub(/url\([^\)]+\)/,'url()') # drop fonts and recursive includes (tracker links in background: URL field)
    end

    def self.cleanAttr node
      node['style'] = (clean node['style'])
    end

    def self.cleanNode node
      node.content = (clean node.inner_text)
    end

  end
end
