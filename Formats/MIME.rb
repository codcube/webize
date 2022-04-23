# coding: utf-8
class WebResource
                                  # non-transformable (MIMEa -> MIMEb) formats
  FixedFormat = /archive|audio|css|image|octet|package|script|video|xz|zip/
  ReFormat = %w(text/html)        # reformatable (MIMEa -> MIMEa) formats

  # file -> MIME type
  def fileMIME
    local = !host
    (!local && fileMIMEattr) ||   # MIME attribute from HTTP metadata
     (local && fileMIMEprefix) || # name prefix from filesystem metadata
      fileMIMEsuffix ||           # name suffix
      fileMIMEsniff ||            # FILE(1)
      (puts "MIME search failed #{fsPath}"; 'application/octet-stream')  # blob
  end

  def fileMIMEattr
    fileAttr :MIME
  end

  def fileMIMEprefix
    name = basename.downcase      # case-normalized name
    if TextFiles.member? name     # well-known textfile basename
      'text/plain'
    elsif name.index('msg.')==0 || path.index('/sent/cur')==0
      'message/rfc822'            # procmail $PREFIX or maildir match
    end
  end

  def fileMIMEsniff
    IO.popen(['file', '-b', '--mime-type', fsPath]).read.chomp
  end

  def fileMIMEsuffix
    suffix = File.extname fsPath
    return if suffix.empty?
    {'.apk' => 'application/vnd.android.package-archive',
    }[suffix] ||                   # native list
    (fileMIMEsuffixRack suffix) || # Rack list
    (fileMIMEsuffixRDF  suffix)    # RDF list
  end

  def fileMIMEsuffixRack suffix; Rack::Mime::MIME_TYPES[suffix] end

  def fileMIMEsuffixRDF suffix
    if format = RDF::Format.file_extensions[suffix[1..-1].to_sym]
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
