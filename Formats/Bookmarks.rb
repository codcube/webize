class Webize::HTML::Reader

  # Reader for bookmarks file export format commonly available in web browsers

  BookmarkDoctype = '<!DOCTYPE NETSCAPE-Bookmark-file-1'

  def bookmarks
    linkCount, tlds, domains = 0, {}, {}
    links = RDF::URI '#links'

    # links container
    yield links, Type, RDF::URI(Container)

    @in.lines.grep(/<A/).map{|a|
      linkCount += 1

      # a = Nokogiri::HTML.fragment(a).css('a')[0]

      # subject = RDF::URI a['href']
      subject = RDF::URI CGI.unescapeHTML a.match(/href=["']?([^'">\s]+)/i)[1]

      subject = HTTP::Node(subject,{}).unproxyURI if %w(l localhost x).member? subject.host

      if subject.host
        # TLD container
        tldname = subject.host.split('.')[-1]
        tld = RDF::URI '#TLD_' + tldname
        tlds[tld] ||= (
          yield links, Contains, tld
          yield tld, Type, RDF::URI(Container)
          yield tld, Title, tldname)

        # hostname container
        host = RDF::URI '#host_' + subject.host
        domains[host] ||= (
          yield tld, Contains, host
          yield host, Title, subject.host
          yield host, Type, RDF::URI(Container)
          yield host, Type, RDF::URI(Directory))

        yield host, Contains, subject
      end

      # title = a.inner_text
      title = CGI.unescapeHTML a.match(/<a[^>]+>([^<]*)/i)[1]

      yield subject, Title, title.sub(/^localhost\//,'')

      # yield subject, Date, Webize.date(a['add_date'])
      yield subject, Date, Webize.date(a.match(/add_date=["']?([^'">\s]+)/i)[1])

      # if icon = a['icon']
      if icon = a.match(/icon=["']?([^'">\s]+)/i)
        # yield subject, Image, RDF::URI(icon)
        yield subject, Image, RDF::URI(CGI.unescapeHTML icon[1])
      end
    }

    yield links, Size, linkCount
  end

end
