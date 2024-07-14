require 'json'
module Webize

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
                   text/json
                   application/manifest+json;q=0.8
                   application/vnd.imgur.v1+json;q=0.1)
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      Identifier = %w(
permalink_url url uri canonical_url
href link src
id ID _id id_str)

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @doc = ::JSON.parse input.respond_to?(:read) ? input.read : input
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
              print ["\e[7m", predicate, "\e[0m "].join
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

        # point to document base from request base
        yield @base.env[:base], Webize::URI(Contains), @base unless @base == @base.env[:base]
        # point to JSON base from document base
        yield @base, Webize::URI(Contains), out              unless @base == out
      end
    end

    # RDF::Graph -> JSON
    # very similar to Graph#to_h, we may switch to that but need to investigate its handling of
    # cyclic structure and bnodes, or do away w/ entirely and hand a RDF::Graph to the render dispatcher.
    # also possibly extend this with backlinks/reverse-arcs using OWL inverse functional properties or Reasoner tools
    def self.fromGraph graph; index = {}

      graph.each_triple{|s,p,o|                           # for each triple, in a
        next if s == o                                    # directed *acyclic* graph:
        p = p.to_s                                        # predicate
        blank = o.class == RDF::Node                      # blank-node object?
        if blank || Identifiable.member?(o.class)         # object is a reference?
          o = index[o] ||= blank ? {} : {'uri' => o.to_s} # dereference object
        end
        index[s] ||= s.node? ? {} : {'uri' => s} # subject
        index[s][p] ||= []                       # predicate
        index[s][p].push o}                      # object

      index # output data-structure, indexable on node identity
    end # JSON-RDF output structure:

    # { uri -> .. ,
    #   predicate -> [123, :symbol, 'string', True,
    #                 {predicate -> [...]}]}

    # some RDF datatypes are supported as Hash keys in Ruby but not in JSON serializations, URI most crucially.
    # attr 'uri' denotes an identifier. without this key, a Hash is treated as a blank node

  end

end
