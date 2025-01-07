module Webize
  module HTML
    class Property
      
      def cache(locations) = locations.map{|l| # POSIX::Node(l['uri']) -> <a>
        {_: :a,
         href: '/' + l.fsPath,
         c: :📦}}

      def origin(locations) = locations.map{|l|
        {_: :a,
         href: l.uri,
         c: :↗,
         class: :origin,
         target: :_blank}}

    end
  end
end
