# coding: utf-8
require 'linkeddata'
class WebResource < RDF::URI
  module URIs
    GlobChars = /[\*\{\[]/
    RegexChars = /[\^\(\)\|\[\]\$]/
    CDNhost = Webize.configRegex 'hosts/CDN'
    CDNdoc = Webize.configRegex 'formats/CDN'
    AllowHosts = Webize.configList 'hosts/allow'
    BlockedSchemes = Webize.configList 'blocklist/scheme'
    Gunk = Webize.configRegex 'blocklist/regex'
    KillFile = Webize.configList 'blocklist/sender'
    Webize.configHash('metadata/constants').map{|symbol, uri|
      self.const_set symbol, uri}
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
      return true if BlockedSchemes.member? scheme           # scheme
      return if !host || (AllowHosts.member? host)           # host
      return true if host.match? Gunk                        # host pattern
      return if host.match?(CDNhost) && path&.match?(CDNdoc) # path pattern
      deny_domain?                                           # domain tree
    end

    def deny_domain?
      d = DenyDomains                                        # reset cursor
      domains.find{|name|                                    # parse name
        return unless d = d[name]                            # advance cursor
        d.empty? }                                           # is name leaf in tree?
    end

    def dirURI?; path && path[-1] == '/' end

    def display_host
      return unless host
      host.sub(/^www\./,'').sub /\.(com|net|org)$/,''
    end

    def display_name
      return fragment if fragment && !fragment.empty?                     # fragment
      return query_values['id'] if query_values&.has_key? 'id' rescue nil # query
      return basename if path && basename && !['','/'].member?(basename)  # basename
      return display_host if host                                         # hostname
      'name'
    end

    def domains; host.split('.').reverse end

    def extname; File.extname path if path end

    def graphURI; [host ? ['//', host] : nil, path].join.R env end

    def imgPath?; path && (ImgExt.member? extname.downcase) end

    def imgURI?; imgPath? || (dataURI? && path.index('image') == 0) end

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

    def secureURL
      if !scheme
        'https:' + uri
      elsif scheme == 'http'
        uri.sub ':', 's:'
      else
        uri
      end
    end
  end

  include URIs
  alias_method :uri, :to_s

  include Console
  Console.logger.verbose! false

  module HTML
    include URIs

    # relocate reference for current browsing context
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

    def uri_toolbar breadcrumbs=nil
      bc = ''                                                       # breadcrumb path
      env[:searchterm] ||= 'q'                                      # query argument

      {class: :toolbox,
       c: [{_: :a, href: host ? env[:base].secureURL : HTTP.qs(env[:qs].merge({'notransform'=>nil})), c: :🧪, id: :UI}, # 👉 origin UI
           {_: :a, href: '/' + fsPath, c: :📦},                                                                         # 👉 archive
           {_: :a, id: :rootpath, href: env[:base].join('/').R(env).href, c: '&nbsp;'*5},                               # 👉 root node
           ({_: :a, c: '↨', id: :tabular,
             href: HTTP.qs(env[:qs].merge({'view' => 'table', 'sort' => 'date'}))} unless env[:view] == 'table'),       # 👉 tabular view
           {class: :path, c: env[:base].parts.map{|p|
              bc += '/' + p                                                                                             # 👉 path breadcrumb
              ['/', {_: :a, class: :path_crumb, href: env[:base].join(bc).R(env).href, c: CGI.escapeHTML(Rack::Utils.unescape p)}]}},
           (breadcrumbs.map{|crumb|                                                                                     # 👉 RDF breadcrumbs
              crumb[Link]&.map{|url|
                u = url.R(env)
                {_: :a, class: :breadcrumb, href: u.href, c: crumb[Title] ? CGI.escapeHTML(crumb[Title].join(' ').strip) : u.display_name,
                 id: 'crumb'+Digest::SHA2.hexdigest(rand.to_s)}}} if breadcrumbs),
           {_: :form, c: [({_: :input, name: env[:searchterm]} unless env[:qs].has_key? env[:searchterm]),              # search box
                          env[:qs].map{|k,v|
                            {_: :input, name: k, value: v}.update(k == env[:searchterm] ? {} : {type: :hidden})}        # query args, hidden in UI except main query text
                         ]}.update(env[:searchbase] ? {action: env[:base].join(env[:searchbase]).R(env).href} : {}),
           env[:feeds].map{|feed|                                                                                       # 👉 feed(s)
             feed = feed.R(env)
             {_: :a, href: feed.href, title: feed.path, c: FeedIcon, id: 'feed' + Digest::SHA2.hexdigest(feed.uri)}.
               update((feed.path||'/').match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {})}, # highlight canonical feed
           (:🔌 if offline?)]} # denote offline request
    end
    
    # URI -> lambda
    Markup = {}          # mark up resource of RDF type
    MarkupPredicate = {} # mark up objects of predicate

    MarkupPredicate['uri'] = -> uris, env {
      uris.map{|uri|
        uri = uri.R env
        {_: :a, href: uri.href, c: uri.display_name}}}

    MarkupPredicate[Link] = -> links, env {
      links.select{|l|l.respond_to? :R}.map(&:R).group_by{|l|
        links.size > 8 && l.host && l.host.split('.')[-1] || nil}.map{|tld, links|
        [{class: :container,
          c: [({class: :head, _: :span, c: tld} if tld),
              {class: :body, c: links.group_by{|l|links.size > 25 ? ((l.host||'localhost').split('.')[-2]||' ')[0] : nil}.map{|alpha, links|
                 ['<table><tr>',
                  ({_: :td, class: :head, c: alpha} if alpha),
                  {_: :td, class: :body,
                   c: {_: :table, class: :links,
                       c: links.group_by(&:host).map{|host, paths|
                         h = ('//' + (host || 'localhost')).R env
                         {_: :tr,
                          c: [{_: :td, class: :host,
                               c: host ? {_: :a, href: h.href,
                                          c: {_: :img, alt: h.display_host, src: h.join('/favicon.ico').R(env).href},
                                          style: "background-color: #{HostColor[host] || '#000'}; color: #fff"} : []},
                              {_: :td, class: :path,
                               c: paths.map{|p| markup p, env }}]}}}},
                  '</tr></table>']}}]}, '&nbsp;']}}

  end
  module HTTP

    def deny status = 200, type = nil
      env[:deny] = true
      ext = File.extname basename if path
      type, content = if type == :stylesheet || ext == '.css'
                        ['text/css', '']
                      elsif type == :font || %w(.eot .otf .ttf .woff .woff2).member?(ext)
                        ['font/woff2', WebResource::HTML::SiteFont]
                      elsif type == :image || %w(.bmp .ico .gif .jpg .png).member?(ext)
                        ['image/png', WebResource::HTML::SiteIcon]
                      elsif type == :script || ext == '.js'
                        ['application/javascript', "// URI: #{uri.match(Gunk) || host}"]
                      elsif type == :JSON || ext == '.json'
                        ['application/json','{}']
                      else
                        env.delete :view
                        env[:qs].map{|k,v|
                          env[:qs][k] = v.R if v && v.index('http')==0 && !v.index(' ')}
                        ['text/html; charset=utf-8', htmlDocument({'#req'=>env})]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => origin,
        'Content-Type' => type},
       head? ? [] : [content]]
    end

    def insecure
      _ = dup.env env
      _.scheme = 'http' if _.scheme == 'https'
      _.env[:base] = _
    end

    # Hash → querystring
    def HTTP.qs h
      return '?' unless h
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
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

  end
end

# class -> WebResource (URI, environment)

class Pathname
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class RDF::URI
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class RDF::Node
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class String
  def R env=nil; env ? WebResource.new(self).env(env) : WebResource.new(self) end
end

class Symbol
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class WebResource
  def R env_=nil; env_ ? env(env_) : self end
end

module Webize
  module URIlist
    class Format < RDF::Format
      content_type 'text/uri-list',
                   extension: :u
      content_encoding 'utf-8'
      reader { Reader }
    end
    class Reader < RDF::Reader
      include Console
      include WebResource::URIs
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
        fn.call RDF::Statement.new @base, Type.R, (Schema+'ItemList').R
        @doc.lines.map(&:chomp).map{|line|
          unless line.empty? || line.match?(/^#/) # skip empty or commented lines
            uri, title = line.split ' ', 2        # URI and optional comment
            uri = uri.R @base.env                 # list-item resource
            item = RDF::Node.new
            fn.call RDF::Statement.new @base, (Schema+'itemListElement').R, item
            fn.call RDF::Statement.new item, Title.R, title || uri.display_name
            fn.call RDF::Statement.new item, (DC + 'identifier').R, uri
          end}
      end
    end
  end

end
