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

    # local cache node URI -> data
    def read
      (File.open POSIX::Node(self).fsPath).read
    end

    # (MIME, data) -> RDF::Repository
    def readRDF format = fileMIME, content = read
      repository = RDF::Repository.new.extend Webize::Graph::Cache

      case format                                                 # content type:TODO needless reads? stop media reads earlier
      when /octet.stream/                                         #  blob
      when /^audio/                                               #  audio
        audio_triples repository
      when /^image/                                               #  image
        repository << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Image))
        repository << RDF::Statement.new(self, RDF::URI(Title), basename)
      when /^video/                                               #  video
        repository << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Video))
        repository << RDF::Statement.new(self, RDF::URI(Title), basename)
      else
        if reader ||= RDF::Reader.for(content_type: format)       # find reader
          reader.new(content, base_uri: self){|_|repository << _} # read RDF

          if format == 'text/html' && reader != RDF::RDFa::Reader # read RDFa
            begin
              RDF::RDFa::Reader.new(content, base_uri: self){|g|
                g.each_statement{|statement|
                  if predicate = Webize::MetaMap[statement.predicate.to_s]
                    next if predicate == :drop
                    statement.predicate = RDF::URI(predicate)
                  end
                  repository << statement
                }}
            rescue
              (logger.debug "⚠️ RDFa::Reader failed on #{uri}")
            end
          end
        else
          logger.warn ["⚠️ no RDF reader for " , format].join # reader not found
        end
      end

      repository
    end

  end
end
