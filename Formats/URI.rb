# coding: utf-8
module Webize

  BasicSlugs = [nil, '', *Webize.configTokens('blocklist/slug')]
  GlobChars = /[\*\{\[]/
  Gunk = Webize.configRegex 'blocklist/regex'
  RegexChars = /[\^\(\)\|\[\]\$]/
  HTTPURI = /^https?:/
  RelURI = /^(http|\/|#)\S*$/

  # define URI constants
  configHash('metadata/constants').map{|symbol, uri|
    const_set symbol, uri }

  class URI < RDF::URI

    def basename
      File.basename path, extname if path
    end

    def dataURI? = scheme == 'data'

    def dirURI? = !path || path[-1] == '/'

    def display_host
      return unless host
      host.sub(/^www\./,'').sub /\.(com|net|org)$/,''
    end

    def display_name
      return uri.split(',')[0] if dataURI?
      return fragment if fragment && !fragment.empty?                     # fragment
     #return query_hash['id'] if query_hash.has_key? 'id'                 # query
      return basename if path && basename && !['','/'].member?(basename)  # basename
      return display_host if host                                         # hostname
      uri
    end

    def domains = host.split('.').reverse

    def extname = (File.extname path if path)

    def graph = URI.new [host ? ['https://', host] : nil,
                         path].join

    def local_id
      if fragment && in_doc?
        fragment
      else
        'r' + Digest::SHA2.hexdigest(rand.to_s)
      end
    end

    def no_scheme = uri.split('//',2)[1]
    def parts = path ? (path.split('/') - ['']) : []

    # Hash → querystring
    def self.qs h
      return '?' unless h
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def query_digest = Digest::SHA2.hexdigest(query)[0..15]

    def query_hash = query_values || {}

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

    def Resource uri
      Resource.new(uri).env env
    end

    # set or get environment
    def env e = nil
      if e
        @env = e
        self
      else
        @env ||= {}
      end
    end

  end

  def self.URI uri
    URI.new uri
  end

  def self.Resource uri, env
    Resource.new(uri).env env
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
        fn.call RDF::Statement.new list, RDF::URI(Type), RDF::URI(Container)
        fn.call RDF::Statement.new @base.env[:base], RDF::URI(Contains), list
        @doc.lines.shuffle.map(&:chomp).map{|line|
          unless line.empty? || line.match?(/^#/) # skip empty and commented lines
            uri, title = line.split ' ', 2        # URI and optional title
            u = Webize::URI(uri)                  # URI-list item
            if u.deny?
              dropCount += 1
            else
              linkCount += 1
              fn.call RDF::Statement.new list, RDF::URI(Contains), u
              fn.call RDF::Statement.new u, RDF::URI(Title), title || uri
            end
          end}
        puts "#{linkCount} URIs. dropped #{dropCount}" unless dropCount == 0
      end
    end
  end
end
