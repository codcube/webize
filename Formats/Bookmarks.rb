module Webize
  module HTML
    class Reader

      # Reader for bookmark format commonly available from web browsers

      BookmarkDoctype = '<!DOCTYPE NETSCAPE-Bookmark-file-1'

      def bookmarks
        linkCount, tlds, domains = 0, {}, {}

        links = RDF::URI '#links'             # bookmark container
        yield @base.env[:base], Contains, links
        yield links, Type, RDF::URI(Container)

        query = @base.env[:qs]['q']&.downcase # query argument

        @in.lines.grep(/<A/).map{|a|          # bookmark(s)
          next if query &&                    # skip bookmark not matching query argument
                  !a.downcase.index(query)

          linkCount += 1                      # increment counter

          # commented code is Nokogiri implementation - regex is significantly faster
         #a = Nokogiri::HTML.fragment(a).css('a')[0] # parse fragment

          subject = RDF::URI CGI.unescapeHTML a.match(/href=["']?([^'">\s]+)/i)[1]
         #subject = RDF::URI a['href']

          subject = HTTP::Node(subject,{}).unproxyURI if %w(l localhost x).member? subject.host

          if subject.host

            # TLD
            tldname = subject.host.split('.')[-1]
            tld = RDF::URI '#TLD_' + tldname
            tlds[tld] ||= (
              yield links, Contains, tld
              yield tld, Type, RDF::URI(Container)
              yield tld, Title, tldname
              yield tld, '#color',
                    '#' + Digest::SHA2.hexdigest(tldname)[0..5]
            )

            # host
            host = RDF::URI '#host_' + subject.host
            domains[host] ||= (
              yield tld, Contains, host
              yield host, Title, subject.host
              yield host, '#style', 'background-color: black'
              yield host, Type, RDF::URI(Container))

            yield host, Schema + 'item', subject
          end

          title = CGI.unescapeHTML a.match(/<a[^>]+>([^<]*)/i)[1]
         #title = a.inner_text

          yield subject, Title, title.sub(/^localhost\//,'')

          yield subject, Date, Webize.date(a.match(/add_date=["']?([^'">\s]+)/i)[1])
         #yield subject, Date, Webize.date(a['add_date'])

          if icon = a.match(/icon=["']?([^'">\s]+)/i)
         #if icon = a['icon']

            yield subject, Image, RDF::URI(CGI.unescapeHTML icon[1])
           #yield subject, Image, RDF::URI(icon)
          end
        }

        yield links, Size, linkCount
      end

    end
  end
end
