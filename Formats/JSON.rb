require 'json'
module Webize

  # JSON-RDF data structure:
  # { uri -> .. ,
  #   predicate -> [123, :symbol, 'string', True,
  #                 {predicate -> [...]}]}

  # some RDF datatypes are supported as Hash keys in Ruby but not in JSON serializations, URI most crucially.
  # attr 'uri' denotes an identifier. without this attribute, a Hash or JSON object is treated as a blank node

  module ActivityStream
    class Format < ::JSON::LD::Format
      content_type 'application/activity+json', extension: :ajson
      reader { ::JSON::LD::Reader }
      writer { ::JSON::LD::Writer }
    end
  end

  module JSON

    Array = /^\[.*\]$/
    Inner = /^[^{'"]*(['"])?({.*})[^}]*$/
    Outer = /^{.*}$/

    class Format < RDF::Format
      content_type 'application/json',
                   extensions: [:json, :meta, :webmanifest],
                   aliases: %w(
                   app/json
                   text/json
                   application/manifest+json;q=0.8
                   application/vnd.imgur.v1+json;q=0.1)
      content_encoding 'utf-8'
      reader { Reader }
      writer { Writer }
    end

    class Reader < RDF::Reader
      format Format

      Identifier = %w(
permalink_url url uri canonical_url
href link src
id ID _id id_str @id)

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @doc = ::JSON.parse input.respond_to?(:read) ? input.read : input
        @options = options
        @unmapped = []

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
        scan_document{|s, p, o, graph = @base|
          fn.call RDF::Statement.new(s, p, o,
                                     graph_name: graph)}
      end
      
      def scan_node node = @doc, graph = @base, &f

        # subject
        subject = if id = Identifier.find{|i| node.has_key? i}  # search for identifier
                    @base.join node.delete id                   # subject URI
                  else
                    RDF::Node.new                               # unidentified node
                  end
        graph = Webize::URI(subject).graph unless subject.node? # graph URI

        # node attributes
        node.map{|k, v|

          # predicates
          predicate = MetaMap[k] || k # map predicate URI

          unless predicate == :drop

            # warn on unmapped predicate. chatty w/ JSON-in-wild's vast array of non-URI attribute names
            unless predicate.match? HTTPURI
              @unmapped.push predicate
              predicate = Schema + predicate
            end

            # objects
            (v.class == Array ? v : [v]).flatten.compact.map{|o|

              object = case o
                       when Hash
                         scan_node o, graph, &f  # recursion on object node
                       when String
                         if predicate == Date # normalize date
                           Webize.date o
                         elsif o.match? RelURI # URI in String
                           @base.join o        # String -> RDF::URI
                         elsif o.match? Outer  # JSON in String
                           Reader.new(o, base_uri: @base).scan_node &f
                         else
                           RDF::Literal o      # String -> RDF::Literal
                         end
                       else
                         o
                       end

              # output triple
              yield subject, Webize::URI(predicate), object, graph
            }
          end}

        subject # return child reference to caller / parent-node
      end

      def scan_document &f

        # if input is Array, wrap it in a node
        if @doc.class == Array
          @doc = {'uri' => @base,
                  Contains => @doc}
        end

        out = scan_node &f # scan base node

        unless @unmapped.empty?
          puts @unmapped.uniq.map{|u|
            ["\e[7m", u, "\e[0m "].join}.join ' '
        end

        # point to document base from request base
        yield @base.env[:base], Webize::URI(Contains), @base unless @base == @base.env[:base]
        # point to JSON base from document base
        yield @base, Webize::URI(Contains), out              unless @base == out
      end
    end

    class Writer < RDF::Writer
      format Format

      def initialize(output = $stdout, **options, &block)
        @graph = RDF::Graph.new
        @base = RDF::URI(options[:base_uri])

        super do
          block.call(self) if block_given?
        end
      end

      def write_triple(subject, predicate, object)
        @graph.insert RDF::Statement.new(subject, predicate, object)
      end

      def write_epilogue
        @output.write (JSON.fromGraph(@graph)[@base] || {}).
                        to_json
      end
    end

    # Graph -> JSON
    # similar to Graph#to_h, we'll switch to that if its bnode and cyclic-structure shapes are compatible
    def self.fromGraph graph

      index = {}                                  # (URI -> node) table

      graph.each_triple{|s,p,o|                   # for each triple, in a
        next if s == o                            # directed *acyclic* graph:
        p = p.to_s                                # predicate

        blank = o.class == RDF::Node              # blank-node object?
        if blank || Identifiable.member?(o.class) # object is a reference?
          o = index[o] ||= blank ? {} : {'uri' => o.to_s} # dereference
        end

        index[s] ||= s.node? ? {} : {'uri' => s}  # subject
        index[s][p] ||= []                        # predicate
        index[s][p].push o}                       # object

      index                                       # output data
    end
 
  end

end
