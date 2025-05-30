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

    def dirURI? = path && path[-1] == '/'

    def display_host
      return unless host
      host.sub(/^www\./,'').sub /\.(com|net|org)$/,''
    end

    def display_name
      return uri.split(',')[0] if dataURI?
      if fragment && !fragment.empty?                     # fragment
        if fragment.index('inline_') == 0
          return '↜'
        else
          return fragment
        end
      end
      return basename if path && basename && !['','/'].member?(basename)  # basename
      return display_host if host                                         # hostname
      uri
    end

    def domains = host.split('.').reverse

    def extname = (File.extname path if path)

    def fsNames = case scheme
                  when 'mid' # RFC2111 mid: URI for RFC822 message
                    id = Digest::SHA2.hexdigest to_s # calculate hash of mid: URI
                    ['mail', id[0..1], id[2..-1]]    #  sharded-hash container
                  when 'tag' # RFC4151 tag: URI primarily emanating from blogging engines
                    id = Digest::SHA2.hexdigest to_s #  calculate hash of tag URI
                    ['mid', id[0..1], id[2..-1]]     #  sharded-hash container
                  else
                    host ? fsNamesGlobal : fsNamesLocal
                  end

    def fsNamesLocal = if parts.empty?
                         %w(.)
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
        @env ||= HTTP.env.update({base: self})
      end
    end

    # list of URIs in uri-list resource
    def uris
      return [] unless extname == '.u'
      pattern = RDF::Query::Pattern.new :s, RDF::URI('#entry'), :o

      storage.read.query(pattern).objects.shuffle.map do |o|
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
        query = @base.env[:qs]['q']&.downcase # query argument

        @doc.lines.map(&:chomp).map{|line| # each line:
          next if line.empty?            # skip empty line
          next if line.match?(/^#/)      # skip commented line
          next if query &&               # skip entry not matching query
                  !line.downcase.index(query)

          uri, title = line.split ' ', 2 # URI, title (String)
          u = Webize::URI(uri)           # URI        (RDF)

          URI::AllowHosts.push u.host if u.deny? # implicit unblock due to list presence. depending on DNS configuration, this might not be enough (script at bin/access/allow adds line to config/hosts/allow)

          graph = RDF::URI('//' + (u.host || 'localhost'))
          fn.call RDF::Statement.new graph, RDF::URI('#entry'), u, graph_name: graph
          fn.call RDF::Statement.new u, RDF::URI(Title), title, graph_name: graph if title
        }
      end
    end
  end

end
