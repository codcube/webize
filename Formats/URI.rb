# coding: utf-8
require 'linkeddata'

module Webize

  # load URI-constant configuration
  configHash('metadata/constants').map{|symbol, uri| const_set symbol, uri }

  class URI < RDF::URI

    AllowHosts = Webize.configList 'hosts/allow'
    BasicSlugs = [nil, '', *Webize.configTokens('blocklist/slug')]
    BlockedSchemes = Webize.configList 'blocklist/scheme'
    CDNdoc = Webize.configRegex 'formats/CDN'
    CDNhost = Webize.configRegex 'hosts/CDN'
    GlobChars = /[\*\{\[]/
    Gunk = Webize.configRegex 'blocklist/regex'
    ImgExt = Webize.configList 'formats/image/ext'
    KillFile = Webize.configList 'blocklist/sender'
    RegexChars = /[\^\(\)\|\[\]\$]/
    DenyDomains = {}

    def self.blocklist
      DenyDomains.clear
      Webize.configList('blocklist/domain').map{|l|          # parse blocklist
        cursor = DenyDomains                                 # reset cursor
        l.chomp.sub(/^\./,'').split('.').reverse.map{|name|  # parse name
          cursor = cursor[name] ||= {}}}                     # initialize and advance cursor
    end
    self.blocklist                                           # load blocklist

    def basename; File.basename path if path end

    def dataURI?; scheme == 'data' end

    def deny?
      return true if BlockedSchemes.member? scheme           # block scheme
      return if !host || (AllowHosts.member? host)           # allow host
      return true if uri.match? Gunk                         # block gunk URI
      return if host.match?(CDNhost) && path&.match?(CDNdoc) # allow CDN URI
      deny_domain?                                           # block domain
    end

    def deny_domain?
      d = DenyDomains                                        # cursor to root
      domains.find{|name|                                    # parse name
        return unless d = d[name]                            # advance cursor
        d.empty? }                                           # is name leaf in tree?
    end

    def dirURI; dirURI? ? self : join((basename || '') + '/').R(env) end
    def dirURI?; !path || path[-1] == '/' end

    def display_host
      return unless host
      host.sub(/^www\./,'').sub /\.(com|net|org)$/,''
    end

    def display_name
      return uri.split(',')[0] if dataURI?
      return fragment if fragment && !fragment.empty?                     # fragment
      return query_values['id'] if query_values&.has_key? 'id' rescue nil # query
      return basename if path && basename && !['','/'].member?(basename)  # basename
      return display_host if host                                         # hostname
      'name'
    end

    def domains; host.split('.').reverse end

    def extname; File.extname path if path end

    def imgPath?; path && (ImgExt.member? extname.downcase) end

    def imgURI?; imgPath? || (dataURI? && path.index('image') == 0) end

    def insecure
      return self if scheme == 'http'
      _ = dup.env env
      _.scheme = 'http'
       _.env[:base] = _
    end

    def no_scheme; uri.split('//',2)[1] end

    def parts; @parts ||= path ? (path.split('/') - ['']) : [] end

    def query_hash; Digest::SHA2.hexdigest(query)[0..15] end

    def on_host? # is URI on request host?
      env[:base].host == host
    end

    def in_doc?  # is URI in request graph?
      on_host? && env[:base].path == path
    end

    def local_id
      if fragment && in_doc?
        fragment
      else
        'r' + Digest::SHA2.hexdigest(rand.to_s)
      end
    end

    # Hash → querystring
    def self.qs h
      return '?' unless h
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def R env_ = nil
      env_ ? env(env_) : self
    end

    def secureURL
      if !scheme
        'https:' + uri
      elsif scheme == 'http'
        uri.sub ':', 's:'
      else
        uri
      end
    end

    def slugs
      re = /[\W_]/
      [(host&.split re),
       parts.map{|p| p.split re},
       (query&.split re),
       (fragment&.split re)]
    end

    # unproxy request/environment URLs
    def unproxy
      r = unproxyURI                                                                             # unproxy URI
      r.scheme ||= 'https'                                                                       # default scheme
      r.host = r.host.downcase if r.host.match? /[A-Z]/                                          # normalize hostname
      env[:base] = r.uri.R env                                                                   # unproxy base URI
      env['HTTP_REFERER'] = env['HTTP_REFERER'].R.unproxyURI.to_s if env.has_key? 'HTTP_REFERER' # unproxy referer URI
      r                                                                                          # origin URI
    end

    # proxy URI -> canonical URI
    def unproxyURI
      p = parts[0]
      return self unless p&.index /[\.:]/ # scheme or DNS name required
      [(p && p[-1] == ':') ? path[1..-1] : ['/', path], query ? ['?', query] : nil].join.R env
    end

    alias_method :uri, :to_s
  end

  module HTML

    # URI -> lambda
    Markup = {}          # markup resource type
    MarkupPredicate = {} # markup objects of predicate

    MarkupPredicate['uri'] = -> us, env {
      (us.class == Array ? us : [us]).map{|uri|
        uri = uri.R env
        {_: :a, href: uri.href, c: :🔗, id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}}


    # relocate reference for request context
    def href
      if in_doc? && fragment         # in-document ref
        '#' + fragment
      elsif env[:proxy_href]         # proxy ref
        if !host || env['SERVER_NAME'] == host # local node
          uri
        else                                   # remote node
          ['http://', env['HTTP_HOST'], '/', scheme ? uri : uri[2..-1]].join
        end
      else                           # URI <-> URL correspondence
        uri
      end
    end

    def toolbar breadcrumbs=nil
      bc = ''                                                       # breadcrumb path

      {class: :toolbox,
       c: [{_: :a, id: :rootpath, href: env[:base].join('/').R(env).href, c: '&nbsp;' * 3},                             # 👉 root node
           {_: :a, id: :UI, href: host ? env[:base].secureURL : URI.qs(env[:qs].merge({'notransform'=>nil})), c: :🧪}, # 👉 origin UI
           {_: :a, id: :cache, href: '/' + fsPath, c: :📦},                                                             # 👉 archive
           ({_: :a, id: :block, href: '/block/' + host.sub(/^www\./,''), class: :dimmed, c: :🛑} if host && !deny_domain?),    # block host
           {_: :span, class: :path, c: env[:base].parts.map{|p|
              bc += '/' + p                                                                                             # 👉 path breadcrumbs
              ['/', {_: :a, id: 'p' + bc.gsub('/','_'), class: :path_crumb,
                     href: env[:base].join(bc).R(env).href,
                     c: CGI.escapeHTML(Rack::Utils.unescape p)}]}},
           (breadcrumbs.map{|crumb|                                                                                     # 👉 graph breadcrumbs
              crumb[Link]&.map{|url|
                u = url.R(env)
                {_: :a, class: :breadcrumb, href: u.href, c: crumb[Title] ? CGI.escapeHTML(crumb[Title].join(' ').strip) : u.display_name,
                 id: 'crumb'+Digest::SHA2.hexdigest(rand.to_s)}}} if breadcrumbs),
           ({_: :form, c: env[:qs].map{|k,v|                                                                            # searchbox
              {_: :input, name: k, value: v}.update(k == 'q' ? {} : {type: :hidden})}} if env[:qs].has_key? 'q'),       # preserve non-visible parameters
           env[:feeds].map{|feed|                                                                                       # 👉 feed(s)
             feed = feed.R(env)
             {_: :a, href: feed.href, title: feed.path, c: FeedIcon, id: 'feed' + Digest::SHA2.hexdigest(feed.uri)}.
               update((feed.path||'/').match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {})}, # highlight canonical feed
           (:🔌 if offline?),                                                                                           # denote offline mode
           {_: :span, class: :stats,
            c: [({_: :span, c: env[:origin_status], class: :bold} if env[:origin_status] && env[:origin_status] != 200),# origin status
                (elapsed = Time.now - env[:start_time] if env.has_key? :start_time                                      # elapsed time
                 [{_: :span, c: '%.1f' % elapsed}, :⏱️] if elapsed > 1)]}]}
    end    
  end
  module URIlist
    class Format < RDF::Format
      content_type 'text/uri-list',
                   extension: :u
      content_encoding 'utf-8'
      reader { Reader }
    end
    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @doc = input.respond_to?(:read) ? input.read : input
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
        list = @base + '#list'
        fn.call RDF::Statement.new list, Type.R, Container.R
        fn.call RDF::Statement.new list, Type.R, Directory.R
        @doc.lines.map(&:chomp).map{|line|
          unless line.empty? || line.match?(/^#/) # skip empty and commented lines
            uri, title = line.split ' ', 2        # URI and optional title
            u = uri.R                             # URI-list item
            fn.call RDF::Statement.new list, Contains.R, u
            fn.call RDF::Statement.new u, Title.R, title || uri
          end}
      end
    end
  end
end

# cast to Webize::URI shorthand method, with optional environment argument
# TODO remove this if doesn't make things too verbose (maybe single R -> Webize::URI constant alias)
class Pathname
  def R env=nil; env ? Webize::URI.new(to_s).env(env) : Webize::URI.new(to_s) end
end

class RDF::URI
  def R env=nil; env ? Webize::URI.new(to_s).env(env) : Webize::URI.new(to_s) end
end

class RDF::Node
  def R env=nil; env ? Webize::URI.new(to_s).env(env) : Webize::URI.new(to_s) end
end

class String
  def R env=nil; env ? Webize::URI.new(self).env(env) : Webize::URI.new(self) end
end

class Symbol
  def R env=nil; env ? Webize::URI.new(to_s).env(env) : Webize::URI.new(to_s) end
end
