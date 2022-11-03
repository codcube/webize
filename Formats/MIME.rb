# coding: utf-8
class WebResource
  # formats we prefer to not (given conneg flexibility) or can not (unimplemented in format library, or
  # negotiation-oblivious clients accepting * at q=1.0 but very confused if MIME changes) transform
  FixedFormat = /archive|audio|css|image|octet|package|script|video|xz|zip/
  # formats we transform even if MIME stays the same
  ReFormat = %w(text/html)
  AV = [Audio, Video, 'RECTANGULAR', 'FORMAT_STREAM_TYPE_OTF'] # audio/video RDF types

  def fileMIME
    (!host && fileMIMEprefix) ||  # name prefix
      fileMIMEsuffix ||           # name suffix
      (logger.warn "MIME search failed #{fsPath}"
       'application/octet-stream') # unknown
  end

  def fileMIMEprefix
    name = basename.downcase      # normalize case
    if TextFiles.member? name     # well-known textfile names (README etc)
      'text/plain'
    elsif name.index('msg.') == 0 || path.index('/sent/cur') == 0
      'message/rfc822'            # procmail $PREFIX or maildir container
    end
  end

  def fileMIMEsuffix
    suffix = File.extname File.realpath fsPath
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

  module HTTP

    # char -> ASCII color
    FormatColor = Webize.configHash 'style/color/format'

    # MIME type -> character
    def format_icon mime
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
