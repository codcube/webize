# coding: utf-8
module Webize
  module MIME

    # formats we prefer to not (given conneg flexibility) or can not (unimplemented in format library,
    # or negotiation-unaware clients accepting * but very confused if MIME changes) transform
    FixedFormat = /archive|audio|css|image|octet|package|script|video|xz|zip/

    # formats we transform even if MIME stays the same
    ReFormat = %w(text/html)

    # audio/video types as RDF URI
    AV = [Audio, Video, 'RECTANGULAR', 'FORMAT_STREAM_TYPE_OTF']

    # plaintext MIME hint for names without extensions, avoids FILE(1) call
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
      name = basename.downcase      # normalize case
      if TextFiles.member? name     # well-known textfile names (README etc)
        'text/plain'
      elsif name.index('msg.') == 0 || path.index('/sent/cur') == 0
        'message/rfc822'            # procmail $PREFIX or maildir container
      end
    end

    def fileMIMEsuffix suffix = (File.extname POSIX::Node(self).realpath) # follow symlink and read suffix
      return if suffix.empty?
      Rack::Mime::MIME_TYPES[suffix] || # Rack map
        fileMIMEsuffixRDF(suffix)       # RDF map
    end

    def fileMIMEsuffixRDF suffix
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
