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
    Inner = /^[^{'"]*(['"])?({.*})[^}]*$/m
    Outer = /^{.*}$/m

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

      def scan_document &f
        yield @base.env[:base], Webize::URI(Contains), @base  # request graph 👉 document
        yield @base, Webize::URI(Contains), scan_fragment(&f) # document 👉 JSON tree-in-graph root node
      end

      # scan JSON Array or Object to RDF node suitable for use in a triple (such as document wrapping above)
      def scan_fragment &f
        scan_node @doc.class == ::Array ? {Contains => @doc} : @doc, @base, &f
      end

      # recursive JSON object scanner
      def scan_node node, graph, &f

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
          next if predicate == :drop

          unless predicate.match? HTTPURI
            puts ["unmapped JSON attr \e[7m", predicate, "\e[0m ", v].join
            predicate = Schema + predicate
          end

          # objects
          (v.class == ::Array ? v : [v]).flatten.map{|o|

            object = case o
                     when Hash
                       scan_node o, graph, &f  # recursion on object node
                     when String
                       if predicate == Date # normalize date
                         Webize.date o
                       elsif predicate == Schema + 'srcSet'
                         o.scan(SRCSET).map{|uri, _|
                           yield subject, Webize::URI(Image), @base.join(uri), graph}
                         nil
                       elsif o.match? RelURI # URI in String
                         @base.join o        # String -> RDF::URI
                       elsif o.match? Array  # JSON Array in String
                         Reader.new(o, base_uri: @base).scan_fragment &f
                       elsif o.match? Outer  # JSON Object in String
                         Reader.new(o, base_uri: @base).scan_fragment &f
                       elsif o.match? /^<.*>$/ # HTML in String
                         HTML::Reader.new(o, base_uri: @base).scan_fragment &f
                       else
                         RDF::Literal o      # String -> RDF::Literal
                       end
                     else
                       o
                     end

            # output triple
            yield subject, Webize::URI(predicate), object, graph if object
          }}

        subject # return child reference to caller / parent-node
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

    # RDF::Graph -> JSON (serializable representation in native ruby values)
    def self.fromGraph graph
      # second stage data reading: RDF::Graph to native ruby values
      # a convenience for user/developer experience, experts may stick to RDF and skip this transformation

      # developer isn't handed soup of unconnected nodes, disjoint subgraphs, left to figure out
      # how to query it with SPARQL or even what RDF is entirely. second-stage read (inlining) outputs
      # native values with familiar Hash-accessor syntax-sugar, utility methods and JSON compatibility

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
