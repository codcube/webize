# coding: utf-8
module Webize

  BasicSlugs = [nil, '', *Webize.configTokens('blocklist/slug')]
  GlobChars = /[\*\{\[]/
  Gunk = Webize.configRegex 'blocklist/regex'
  RegexChars = /[\^\(\)\|\[\]\$]/
  HTTPURI = /^https?:/
  DataURI = /^data:\S*$/
  RelURI = /^(http|\/|#)\S*$/

  # define URI constants
  configHash('metadata/constants').map{|symbol, uri|
    const_set symbol, uri }

  # map constants to prefix symbols for RDF serializer
  Prefixes = {
    dc: DC,
    ldp: LDP,
    rdfs: RDFs,
    schema: Schema,
    sioc: SIOC,
    xhv: XHV
  }

  class URI < RDF::URI

    def basename
      File.basename path if path
    end

    # basename sans extension
    def barename
      File.basename path, extname if path
    end

    def dataURI? = scheme == 'data'

    def dirname = File.dirname fsPath

    def dirURI? = !path || path[-1] == '/'

    def display_host
      return unless host
      host.sub(/^www\./,'').sub /\.(com|net|org)$/,''
    end

    def display_name
      return uri.split(',')[0] if dataURI?
      return fragment if fragment && !fragment.empty?                     # fragment
      return basename if path && basename && !['','/'].member?(basename)  # basename
      return display_host if host                                         # hostname
      uri
    end

    def domains = host.split('.').reverse

    def extname = (File.extname path if path)

    def fsNames = host ? fsNamesGlobal : fsNamesLocal

    def fsNamesLocal = if parts.empty?
                         %w(.)
                       elsif parts[0] == 'msg'                                          # message
                         id = Digest::SHA2.hexdigest Rack::Utils.unescape_path parts[1] #  calculate hash of message identifier
                         ['mail', id[0..1], id[2..-1]]                                  #  sharded-hash container
                       else                                                             # path map
                         unescape_parts
                       end

    def fsNamesGlobal = [domains,                            # domain-name container
                         if (path && path.size > 496) || parts.find{|p|p.size > 127}
                           hash = Digest::SHA2.hexdigest uri # oversize path or segment(s), calculate hash of URI
                           [hash[0..1], hash[2..-1]]         # sharded-hash container
                         else
                           if query
                             Webize::URI join fsNamesQuery.join '.'
                           else
                             self
                           end.unescape_parts                # path map
                         end].flatten

    def fsNamesQuery = [barename,                            # basename sans extension
                        Digest::SHA2.hexdigest(query)[0..9], # query hash
                        extname] - ['']                      # extension

    # URI -> pathname
    def fsPath = fsNames.join '/'

    def graph = URI.new split('#')[0]

    def no_scheme = uri.split('//',2)[1]

    def parts = path ? (path.split('/') - ['']) : []

    # Hash → querystring
    def self.qs h
      return '?' unless h
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def query_hash = query_values || {}

    def split(*a) = uri.split *a

    def slugs
      re = /[\W_]/
      [(host&.split re),
       parts.map{|p| p.split re},
       (query&.split re),
       (fragment&.split re)]
    end

    def unescape_parts = parts.map do |part|
      Rack::Utils.unescape_path part
    end

    alias_method :uri, :to_s
  end

  # a Webize Resource is an RDF Resource and an environment
  class Resource < URI

    def Resource uri
      Resource.new(uri).env env
    end

    # base-URI accessor
    def base = env[:base]

    # set or get environment
    def env e = nil
      if e
        @env = e
        self
      else
        @env ||= {}
      end
    end

    # list of URIs in uri-list resource
    def uris
      return [] unless extname == '.u'
      pattern = RDF::Query::Pattern.new :s, RDF::URI('#graph'), :o

      storage.read.query(pattern).objects.map do |o|
        Webize::Resource o, env
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
        @options = options
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
        list = @base + '#list'                # list URI
                                              # 👉 list
        fn.call RDF::Statement.new @base, RDF::URI(Contains), list
        query = @base.env[:qs]['q']&.downcase # query argument

        @doc.lines.map(&:chomp).map{|line| # each line:
          next if line.empty?            # skip empty line
          next if line.match?(/^#/)      # skip commented line
          next if query &&               # skip entry not matching query
                  !line.downcase.index(query)

          uri, title = line.split ' ', 2 # URI, title (String)
          u = Webize::URI(uri)           # URI        (RDF)

          URI::AllowHosts.push u.host if u.deny? # depending on DNS configuration, list presence might not be enough for implicit unblock

          fn.call RDF::Statement.new list, RDF::URI('#graph'), u
          fn.call RDF::Statement.new u, RDF::URI(Title), title || uri unless img
        }
      end
    end
  end

end
