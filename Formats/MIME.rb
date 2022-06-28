# coding: utf-8
class WebResource

  FixedFormat = /archive|audio|css|image|octet|package|video|xz|zip/ # formats we can't currently transform. TODO ffmpeg backend for conneg media-transcode
  ReFormat = %w(text/html)                                           # formats we transform even if MIME stays the same, aka reformat
  AV = [Audio, Video, 'RECTANGULAR', 'FORMAT_STREAM_TYPE_OTF']       # audio/video RDF types

  # filename -> MIME type mappings

  MimeTypes = {'.apk' => 'application/vnd.android.package-archive'}

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
    MimeTypes[suffix] ||                # local preference
      Rack::Mime::MIME_TYPES[suffix] || # Rack library
      fileMIMEsuffixRDF(suffix)         # RDF library
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

    def selectFormat default = nil                          # default-format argument
      default ||= 'text/html'                               # default when unspecified
      return default unless env.has_key? 'HTTP_ACCEPT'      # no preference specified
      category = (default.split('/')[0] || '*') + '/*'      # format-category wildcard symbol
      all = '*/*'                                           # any-format wildcard symbol

      index = {}                                            # build (q-value → format) index
      env['HTTP_ACCEPT'].split(/,/).map{|e|                 # header values
        fmt, q = e.split /;/                                # (MIME, q-value) pair
        i = q && q.split(/=/)[1].to_f || 1                  # default q-value
        index[i] ||= []                                     # q-value entry
        index[i].push fmt.strip}                            # insert format at q-value

      index.sort.reverse.map{|_, accepted|                  # search in descending q-value order
        return default if accepted.member? all              # anything accepted here
        return default if accepted.member? category         # category accepted here
        accepted.map{|format|
          return format if RDF::Writer.for(:content_type => format) || # RDF writer available for format
             ['application/atom+xml','text/html'].member?(format)}}    # non-RDF writer available
      default                                               # search failure, use default
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
