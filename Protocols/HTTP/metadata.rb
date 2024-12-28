module Webize
  module HTTP
    
    def self.debug? = ENV['CONSOLE_LEVEL'] == 'debug'

    # initialize environment
    # these are being deprecated in favor of RDF in the request graph describing the base URI
    def self.env = {
      feeds: [],     # feed pointers
      fragments: {}, # fragment list for deduplication
      images: {},    # image list for deduplication
      links: {},     # Link headers
      mapped: {},    # mapped URI statistics
      qs: {},        # parsed query-string
      warnings: []}  # warnings

  end
  class HTTP::Node

    # host adaptation runs on last (origin facing) proxy in chain
    def adapt? = !ENV.has_key?('http_proxy')

    def clientETags
      return [] unless env.has_key? 'HTTP_IF_NONE_MATCH'
      env['HTTP_IF_NONE_MATCH'].strip.split /\s*,\s*/
    end

    # current (y)ear (m)onth (d)ay (h)our -> URI for timeslice
    def dateDir
      ps = parts
      loc = Time.now.utc.strftime(case ps[0].downcase
                                  when 'y'
                                    hdepth = 3 ; '/%Y/'
                                  when 'm'
                                    hdepth = 2 ; '/%Y/%m/'
                                  when 'd'
                                    hdepth = 1 ; '/%Y/%m/%d/'
                                  when 'h'
                                    hdepth = 0 ; '/%Y/%m/%d/%H/'
                                  else
                                  end)
      globbed = ps[1]&.match? GlobChars

      # convert search term to glob pattern
      pattern = ['*/' * hdepth,                       # glob less-significant (sub)slices in slice
                 globbed ? nil : '*', ps[1],          # globify slug if bare
                 globbed ? nil : '*'] if ps.size == 2 # .. if slug provided

      qs = ['?', env['QUERY_STRING']] if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?

      redirect [loc, pattern, qs].join # redirect to timeslice
    end

    def debug? = ENV['CONSOLE_LEVEL'] == 'debug'

    # navigation pointers in HTTP metadata
    def dirMeta
      root = !path || path == '/'
      if host && root
        # up to parent domain
        env[:links][:up] = '//' + host.split('.')[1..-1].join('.')
      elsif !root
        # up to parent node
        env[:links][:up] = [File.dirname(env['REQUEST_PATH']), '/', (env['QUERY_STRING'] && !env['QUERY_STRING'].empty?) ? ['?',env['QUERY_STRING']] : nil].join
      end
      # down to child node(s)
      if env[:preview]
        env[:links][:down] = URI.qs(env[:qs].merge({'full' => nil}))
      elsif dirURI? && !host
        env[:links][:down] = '*'
      end
    end

    # unique identifier for file version
    def fileETag = Digest::SHA2.hexdigest [self,
                                           storage.mtime,
                                           storage.size].join

    def head? = env['REQUEST_METHOD'] == 'HEAD'

    # client<>proxy and internal headers not reused on proxy<>origin connection
    SingleHopHeaders = Webize.configTokens 'blocklist/header'

    # header massaging happens here
    def headers raw = nil
      raw ||= env || {}                               # raw headers
      head = {}                                       # cleaned headers
      logger.debug ["\e[7m raw headers 🥩🗣 \e[0m #{uri}\n", HTTP.bwPrint(raw)].join if debug? # raw debug-prints

      # restore HTTP RFC names from mangled CGI names - PRs pending for rack/falcon, maybe we can remove this
      raw.map{|k,v|                                   # (key, val) tuples
        unless k.class!=String || k.match?(/^(protocol|rack)\./i) # except rack/server-use fields
          key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip HTTP prefix and split tokens
            if %w{cf cl csrf ct dfe dnt id spf utc xss xsrf}.member? t
              t.upcase                                # upcase acronym
            elsif 'etag' == t
              'ETag'                                  # partial acronym
            else
              t.capitalize                            # capitalize word
            end}.join '-'                             # join words
          head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless SingleHopHeaders.member? key.downcase # set header
        end}

      head['Content-Type'] = 'application/json' if %w(api.mixcloud.com).member? host

      head['Last-Modified']&.sub! /((ne|r)?s|ur)?day/, '' # abbr day name to 3-letter variant

      head['Link'].split(',').map{|link|             # read Link headers to request env
        ref, type = link.split(';').map &:strip
        if ref && type
          ref = ref.sub(/^</,'').sub />$/, ''
          type = type.sub(/^rel="?/,'').sub /"$/, ''
          env[:links][type.to_sym] = ref
        end} if head.has_key? 'Link'

      head['Referer'] = 'http://drudgereport.com/' if host&.match? /wsj\.com$/ # referer tweaks so stuff loads
      head['Referer'] = 'https://' + (host || env['HTTP_HOST']) + '/' if (path && %w(.gif .jpeg .jpg .png .svg .webp).member?(File.extname(path).downcase)) || parts.member?('embed')
      head.delete 'Referer' if host == 'www.reddit.com' # existence of referer causes empty RSS feed 

      head['User-Agent'] = 'curl/7.82.0' if %w(po.st t.co).member? host # prefer HTTP (HEAD) redirects over procedural Javascript - advertise a basic user-agent

      logger.debug ["\e[7m clean headers 🧽🗣 \e[0m #{uri}\n", HTTP.bwPrint(head)].join if debug? # clean debug-prints

      head
    end

    def icon
      return unless env[:links].has_key? :icon
      fav = POSIX::Node join '/favicon.ico'                                 # default location
      icon = env[:links][:icon] = POSIX::Node env[:links][:icon], env       # icon location
      if !icon.dataURI? && icon.path != fav.path && icon != self &&         # if icon is in non-default location and
         !icon.directory? && !fav.exist? && !fav.symlink?                   # default location is available:
        fav.mkdir                                                           # create container
        FileUtils.ln_s (icon.node.relative_path_from fav.dirname), fav.node # link icon to default location
      end
    end

    def linkHeader
      return unless env.has_key? :links
      env[:links].map{|type,uri|
        "<#{uri}>; rel=#{type}"}.join(', ')
    end

    def normalize_charset c
      c = case c
          when /iso.?8859/i
            'ISO-8859-1'
          when /s(hift)?.?jis/i
            'Shift_JIS'
          when /utf.?8/i
            'UTF-8'
          when /win.*1252/i
            'Windows-1252'
          else
            c
          end
      unless Encoding.name_list.member? c          # ensure charset is in encoding set
        logger.debug "⚠️ unsupported charset #{c} on #{uri}"
        c = 'UTF-8'                                # default charset
      end
      c
    end

    def origin
      if env['HTTP_ORIGIN']
        env['HTTP_ORIGIN']
      elsif env[:referer]
        ['http', host == 'localhost' ? '' : 's', '://', env[:referer].host].join
      else
        '*'
      end
    end

    # format selection aka content-negotiation
    def selectFormat default = nil                     # default-format argument
      default ||= 'text/html'                          # default when unspecified
      return default unless env.has_key? 'HTTP_ACCEPT' # no preference specified
      category = (default.split('/')[0] || '*') + '/*' # format-category wildcard symbol
      all = '*/*'                                      # any-format wildcard symbol

      index = {}                                       # build (q-value → format) index
      env['HTTP_ACCEPT'].split(/,/).map{|e|            # header values
        fmt, q = e.split /;/                           # (MIME, q-value) pair
        i = q && q.split(/=/)[1].to_f || 1             # default q-value
        index[i] ||= []                                # q-value entry
        index[i].push fmt.strip}                       # insert format at q-value

      index.sort.reverse.map{|_, accepted|             # search in descending q-value order
        return default if accepted.member? all         # anything accepted here
        return default if accepted.member? category    # category accepted here
        accepted.map{|format|
          return format if RDF::Writer.for(:content_type => format) || # RDF writer available for format
             ['application/atom+xml','text/html'].member?(format)}}    # non-RDF writer available
      default                                          # default format
    end

    # temporal pointers in HTTP metadata
    def timeMeta
      return if host # some remote hosts have these dirs, but not enough to bother looking

      n = nil # next-page locator
      p = nil # prev-page locator

      # path components
      ps = parts # all parts
      dp = []    # datetime parts
      dp.push ps.shift.to_i while ps[0] && ps[0].match(/^[0-9]+$/)

      case dp.length
      when 1 # Y
        year = dp[0]
        n = '/' + (year + 1).to_s
        p = '/' + (year - 1).to_s
      when 2 # Y-m
        year = dp[0]
        m = dp[1]
        n = m >= 12 ? "/#{year + 1}/#{01}" : "/#{year}/#{'%02d' % (m + 1)}"
        p = m <=  1 ? "/#{year - 1}/#{12}" : "/#{year}/#{'%02d' % (m - 1)}"
      when 3 # Y-m-d
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          p = (day-1).strftime('/%Y/%m/%d')
          n = (day+1).strftime('/%Y/%m/%d')
        end
      when 4 # Y-m-d-H
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          hour = dp[3]
          p = hour <=  0 ? (day - 1).strftime('/%Y/%m/%d/23') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour-1)))
          n = hour >= 23 ? (day + 1).strftime('/%Y/%m/%d/00') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour+1)))
        end
      end

      # previous, next, parent pointers

      q = (env['QUERY_STRING'] && !env['QUERY_STRING'].empty?) ? ('?'+env['QUERY_STRING']) : ''

      env[:links][:up] = [nil, dp[0..-2].map{|n| '%02d' % n}, '*', ps].join('/') + q if dp.length > 1 && ps[-1] != '*' && ps[-1]&.match?(GlobChars)
      env[:links][:prev] = [p, ps].join('/') + q + '#prev' if p
      env[:links][:next] = [n, ps].join('/') + q + '#next' if n
    end

  end
end
