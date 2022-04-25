# coding: utf-8
class WebResource
                                  # non-transformable (MIMEa -> MIMEb) formats
  FixedFormat = /archive|audio|css|image|octet|package|script|video|xz|zip/
  MimeTypes = {'.apk' => 'application/vnd.android.package-archive'}
  ReFormat = %w(text/html)        # reformatable (MIMEa -> MIMEa) formats

  # file -> MIME type
  def fileMIME
    (!host && fileMIMEprefix) ||  # name prefix
      fileMIMEsuffix ||           # name suffix
      (puts "MIME search failed #{fsPath}"
       'application/octet-stream') # unknown
  end

  def fileMIMEprefix
    name = basename.downcase      # normalize case
    if TextFiles.member? name     # well-known textfiles
      'text/plain'
    elsif name.index('msg.') == 0 || path.index('/sent/cur') == 0
      'message/rfc822'            # procmail $PREFIX or maildir container
    end
  end

  def fileMIMEsuffix
    suffix = File.extname File.realpath fsPath
    return if suffix.empty?
    MimeTypes[suffix] ||                # webize list
      Rack::Mime::MIME_TYPES[suffix] || # Rack list
      fileMIMEsuffixRDF(suffix)         # RDF list
  end

  def fileMIMEsuffixRDF suffix
    if format = RDF::Format.file_extensions[suffix[1..-1].to_sym]
      puts ['multiple formats match extension', suffix, format, ', using', format[0]].join ' ' if format.size > 1
      format[0].content_type[0]
    end
  end

  module HTTP

    # character -> ASCII color
    FormatColor = {
      ➡️: '38;5;7',
      📃: '38;5;231',
      📜: '38;5;51',
      🗒: '38;5;165',
      🐢: '38;5;48',
      🎨: '38;5;227',
      🖼️: '38;5;226',
      🎬: '38;5;208'}

    # MIME type -> character
    def format_icon mime
      case mime
      when /^(application\/)?font/
        :🇦
      when /^audio/
        :🔉
      when /^image/
        :🖼️
      when /^video/
        :🎞️
      when /atom|rss|xml/
        :📰
      when /html/
        :📃
      when /json/
        :🗒
      when /markdown/
        :🖋
      when /n.?triples/
        :⑶
      when /octet.stream|zip|xz/
        :🧱
      when /playlist/
        :🎬
      when /script/
        :📜
      when /text\/css/
        :🎨
      when /text\/gemini/
        :🚀
      when /text\/plain/
        :🇹
      when /text\/turtle/
        :🐢
      else
        mime
      end
    end
  end
end

module Webize

  def self.clean baseURI, body, format
    if format.index('text/css') == 0     # clean CSS
      Webize::CSS.clean body
    elsif format.index('text/html') == 0 # clean HTML
      Webize::HTML.clean body, baseURI
    else
      body
    end
  end

end
