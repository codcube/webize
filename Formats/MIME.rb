
# enable 🐢 extension for Turtle
RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl]

module Webize
  class URI

    CDN_doc = Webize.configRegex 'formats/CDN'
    FontExt = Webize.configList 'formats/font/ext'
    ImageExt = Webize.configList 'formats/image/ext'
    ImageHost = Webize.configList 'formats/image/host'
    VideoExt = Webize.configList 'formats/video/ext'
    VideoHost = Webize.configList 'formats/video/host'

    def CDN_doc? = host&.match?(CDN_hosts) && path&.match?(CDN_doc)

    def fontURI? = FontExt.member? extname&.downcase

    def imageData? = dataURI? &&
                     path.index('image') == 0
    alias_method :imgData?, :imageData?

    def imageHost? = ImageHost.member?(host)
    alias_method :imgHost?, :imageHost?

    def imagePath? = path &&
                     (ImageExt.member?(extname.downcase) || # image extension
                      %w(@jpeg @webp @png).member?(path[-5..-1])) # @ as extension separator
    alias_method :imgPath?, :imagePath?

    def imageURI? = imagePath? ||
                    imageHost? ||
                    imageData? ||
                    (%w(jpg png).member? query_hash['format'])
    alias_method :imgURI?, :imageURI?

    def videoHost? = VideoHost.member?(host)
    #alias_method :vidHost?, :videoHost?

    def videoPath? = path &&
                     VideoExt.member?(extname.downcase)
    #alias_method :vidPath?, :videoPath?

    def videoURI? = videoPath? ||
                    videoHost?
    #alias_method :vidURI?, :videoURI?

  end
  module MIME

    # format URIs <https://www.w3.org/ns/formats/>

    # formats we prefer to not (content-negotiation) or can not (unimplemented) transform
    FixedFormat = /audio|css|image|octet|script|video|zip/

    # indexing preferences:
    # for HTTP everything is indexed after a network read, unless no transcoding or merging is occurring ("static asset" fetches)
    # for POSIX (files encountered on local or network fs) we only index explicity listed formats

    # query args are passed to readers so you can do quite a bit of ad-hoc querying without an indexing pass
    # so far, indexing is used when a graph pointer needs to be at an alternate location to wherever a file is
    # e.g: - email findable at a Message-ID derived location
    #      - Atom/RSS feed's posts at their canonical post URI and timeline locations

    IndexedFormats = %w(
application/rss+xml
message/rfc822)

    # formats we transform even if MIME stays the same
    ReFormat = %w(text/html)

    # plaintext MIME hint for names without extensions, avoids FILE(1) call when there's no upstream Content-Type metadata cached
    TextFiles = %w(changelog copying license readme todo)

    # MIME -> ASCII color
    Color = Webize.configHash 'style/color/format'

    def fileMIME
      (!host && fileMIMEprefix) ||  # name prefix
        fileMIMEsuffix ||           # name suffix
        (logger.warn "MIME search failed for #{uri}" # TODO bring back FILE(1)?
         'application/octet-stream') # unknown MIME
    end

    def fileMIMEprefix
      name = (File.basename path, extname).downcase # strip suffix and normalize case
      if TextFiles.member?(name) && extname.empty?
        'text/plain'           # well-known textfile name
      elsif name == 'msg'
        'message/rfc822'       # procmail $PREFIX or maildir container
      end
    end

    # fs-state dependent (suffix -> MIME) map
    def fileMIMEsuffix
      MIME.fromSuffix POSIX::Node(self).extension
    end

    # name-mapped/pure (suffix -> MIME) map
    def self.fromSuffix suffix
      return if !suffix || suffix.empty?
      fromSuffixRack(suffix) || # Rack index
        fromSuffixRDF(suffix)   # RDF index
    end

    def self.fromSuffixRack suffix
      Rack::Mime::MIME_TYPES[suffix]
    end

    def self.fromSuffixRDF suffix
      if format = RDF::Format.file_extensions[suffix[1..-1].to_sym]
        logger.warn ['multiple formats match extension', suffix, format, ', using', format[0]].join ' ' if format.size > 1
        format[0].content_type[0]
      end
    end

    # MIME type -> character
    def self.format_icon mime
      case mime
      when /^(application\/)?font/
        '🇦'
      when /^audio/
        '🔉'
      when /^image/
        '🖼️'
      when /^video/
        '🎞️'
      when /atom|rss|xml/
        '📰'
      when /html/
        '📃'
      when /json/
        '🗒'
      when /markdown/
        '🖋'
      when /n.?triples/
        '⑶'
      when /octet.stream|zip|xz/
        '🧱'
      when /pdf/
        '📚'
      when /playlist/
        '🎬'
      when /script/
        '📜'
      when /text\/css/
        '🎨'
      when /text\/gemini/
        '🚀'
      when /text\/plain/
        '🇹'
      when /text\/turtle/
        '🐢'
      else
        mime
      end
    end
  end
end
