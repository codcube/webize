module Webize
  module HTML
    class Reader

      # Reader for bookmark format commonly available from web browsers

      BookmarkDoctype = '<!DOCTYPE NETSCAPE-Bookmark-file-1'

      def bookmarks
        linkCount, tlds, domains = 0, {}, {}

        links = RDF::URI '#links'             # bookmark container
        yield @base.env[:base], Contains, links

        query = @base.env[:qs]['q']&.downcase # query argument

        @in.lines.grep(/<A/).map{|a|          # bookmark(s)
          next if query &&                    # skip bookmark not matching query argument
                  !a.downcase.index(query)

          linkCount += 1                      # increment counter

          # a = Nokogiri::HTML.fragment(a).css('a')[0] # nokogiri

          subject = RDF::URI CGI.unescapeHTML a.match(/href=["']?([^'">\s]+)/i)[1] # regex
          #subject = RDF::URI a['href']                                            # nokogiri

          subject = HTTP::Node(subject,{}).unproxyURI if %w(l localhost x).member? subject.host

          if subject.host

            # TLD
            tldname = subject.host.split('.')[-1]
            tld = RDF::URI '#TLD_' + tldname
            tlds[tld] ||= (
              yield links, Contains, tld
              yield tld, Title, tldname
              yield tld, '#color',
                    '#' + Digest::SHA2.hexdigest(tldname)[0..5]
            )

            # host
            host = RDF::URI '#host_' + subject.host
            domains[host] ||= (
              yield tld, Contains, host
              yield host, Title, subject.host
            )

            yield host, '#graph', subject
          end

          title = CGI.unescapeHTML a.match(/<a[^>]+>([^<]*)/i)[1] # regex
         #title = a.inner_text                                    # nokogiri

          yield subject, Title, title.sub(/^localhost\//,'')
                                                                  # regex
          yield subject, Date, Webize.date(a.match(/add_date=["']?([^'">\s]+)/i)[1])
         #yield subject, Date, Webize.date(a['add_date'])         # nokogiri

          if icon = a.match(/icon=["']?([^'">\s]+)/i)             # regex
         #if icon = a['icon']                                     # nokogiri

            yield subject, Image, RDF::URI(CGI.unescapeHTML icon[1]) # regex
           #yield subject, Image, RDF::URI(icon)                  # nokogiri
          end
        }

        yield links, Size, linkCount
      end

    end
  end
end
