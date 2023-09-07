# coding: utf-8
require 'linkeddata'

module Webize

  BasicSlugs = [nil, '', *Webize.configTokens('blocklist/slug')]
  GlobChars = /[\*\{\[]/
  Gunk = Webize.configRegex 'blocklist/regex'
  RegexChars = /[\^\(\)\|\[\]\$]/

  # load URI-constant configuration
  configHash('metadata/constants').map{|symbol, uri| const_set symbol, uri }

  class URI < RDF::URI

    AllowHosts = Webize.configList 'hosts/allow'
    BlockedSchemes = Webize.configList 'blocklist/scheme'
    CDNdoc = Webize.configRegex 'formats/CDN'
    CDNhost = Webize.configRegex 'hosts/CDN'
    ImgExt = Webize.configList 'formats/image/ext'
    KillFile = Webize.configList 'blocklist/sender'
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
      return true if BlockedSchemes.member? scheme                  # block scheme
      return true if uri.match? Gunk                                # block URI patterns
      return false if host&.match?(CDNhost) && path&.match?(CDNdoc) # allow URI patterns on host
      return deny_domain?                                           # allow or block domain
    end

    def deny_domain?
      return false if !host || AllowHosts.member?(host)             # allow host
      d = DenyDomains                                               # cursor to base of tree
      domains.find{|name|                                           # parse domain name
        return unless d = d[name]                                   # advance cursor
        d.empty? }                                                  # named leaf exists in tree?
    end

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
      uri
    end

    def domains; host.split('.').reverse end

    def extname; File.extname path if path end

    def imgPath?; path && (ImgExt.member? extname.downcase) end

    def imgURI?; imgPath? || (dataURI? && path.index('image') == 0) end

    def local_id
      if fragment && in_doc?
        fragment
      else
        'r' + Digest::SHA2.hexdigest(rand.to_s)
      end
    end

    def no_scheme; uri.split('//',2)[1] end
    def parts; path ? (path.split('/') - ['']) : [] end

    # Hash → querystring
    def self.qs h
      return '?' unless h
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def query_hash; Digest::SHA2.hexdigest(query)[0..15] end

    def slugs
      re = /[\W_]/
      [(host&.split re),
       parts.map{|p| p.split re},
       (query&.split re),
       (fragment&.split re)]
    end

    alias_method :uri, :to_s
  end

  # a Webize Resource is an RDF Resource and an environment
  class Resource < URI

    # set or get environment
    def env e = nil
      if e
        @env = e
        self
      else
        @env ||= {}
      end
    end

    def relocate?
      [FWD_hosts,
       URL_hosts,
       YT_hosts].find{|group|
        group.member? host}
    end

    def relocate
      Resource.new(if FWD_hosts.member? host
                   ['//', FWD_hosts[host], path].join
                  elsif URL_hosts.member? host
                    q = query_values || {}
                    q['url'] || q['u'] || q['q'] || self
                  elsif YT_hosts.member? host
                    ['//www.youtube.com/watch?v=', (query_values || {})['v'] || path[1..-1]].join
                  else
                    self
                   end, env)
  end

    # relocate URI to current environment
    def href
      if in_doc? && fragment # local reference
        '#' + fragment
      elsif env[:proxy_href] # proxy reference:
        if !host || env['SERVER_NAME'] == host
          uri                #  local node
        else                 #  remote node
          ['http://', env['HTTP_HOST'], '/', scheme ? uri : uri[2..-1]].join
        end
      else                   # direct URI<>URL map
        uri
      end
    end

    # set scheme to HTTP for fetch method/library protocol selection for peer nodes on private/local networks
    def insecure
      return self if scheme == 'http'
      _ = dup.env env
      _.scheme = 'http'
       _.env[:base] = _
    end

    def in_doc?  # is URI in request graph?
      on_host? && env[:base].path == path
    end

    def offline?
      ENV.has_key? 'OFFLINE'
    end

    def on_host? # is URI on request host?
      env[:base].host == host
    end

  end

  def self.Resource u, e
    Resource.new(u).env e
  end

  def self.URI u
    URI.new u
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
        dropCount, linkCount = [0, 0] # stats
        fn.call RDF::Statement.new list, Type.R, Container.R
        fn.call RDF::Statement.new list, Type.R, Directory.R
        @doc.lines.shuffle.map(&:chomp).map{|line|
          unless line.empty? || line.match?(/^#/) # skip empty and commented lines
            uri, title = line.split ' ', 2        # URI and optional title
            u = uri.R                             # URI-list item
            if u.deny?
              dropCount += 1
            else
              linkCount += 1
              fn.call RDF::Statement.new list, Contains.R, u
              fn.call RDF::Statement.new u, Title.R, title || uri
            end
          end}
        puts "#{linkCount} URIs. dropped #{dropCount}" unless dropCount == 0
      end
    end
  end
end

class String
  def R; Webize::URI self end
end
