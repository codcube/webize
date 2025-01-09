module Webize
  module HTML
    class Reader

      # Reader for bookmark format commonly available from web browsers

      BookmarkDoctype = '<!DOCTYPE NETSCAPE-Bookmark-file-1'

      def bookmarks
        query = @base.env[:qs]['q']&.downcase # query argument

        @in.lines.grep(/<A/).map{|a|          # bookmark(s)
          next if query &&                    # skip bookmark not matching query argument
                  !a.downcase.index(query)

          ## nokogiri implementation (slow, pretty, potentially less bugs)
          #a = Nokogiri::HTML.fragment(a).css('a')[0]
          #subject = RDF::URI a['href']
          #title = a.inner_text
          #yield subject, Date, Webize.date(a['add_date'])
          #if icon = a['icon']
          #yield subject, Image, RDF::URI(icon)

          ## regex implementation (fast and ugly)
          subject = Webize::URI CGI.unescapeHTML a.match(/href=["']?([^'">\s]+)/i)[1]
          subject = HTTP::Node(subject,{}).unproxyURI if %w(l localhost x).member? subject.host
          graph = subject.graph

          title = CGI.unescapeHTML a.match(/<a[^>]+>([^<]*)/i)[1]

          yield subject, Title, title.sub(/^localhost\//,''), graph
          yield subject, Date, Webize.date(a.match(/add_date=["']?([^'">\s]+)/i)[1]), graph
          if icon = a.match(/icon=["']?([^'">\s]+)/i)
            yield subject, Image, RDF::URI(CGI.unescapeHTML icon[1]), graph
          end}
      end

    end
  end
end
