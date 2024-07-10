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

        # if output has no identifier, point to it from base/identified node
        yield @base, Webize::URI(Contains), out if out.node?
      end
    end

    # RDF::Graph -> JSON
    # very similar to #to_h in RDF.rb, we may switch to that but need to investigate its handling of
    # cycles and blank nodes, or do away w/ entirely and hand a RDF::Graph to the render dispatcher,
    # or extend to automagically add backlinks/reverse-arcs using OWL inverse functional properties
    def self.fromGraph graph
      index = {}                        # node index

      graph.each_triple{|subj,pred,obj| # triple
        s = subj.to_s                   # subject
        p = pred.to_s                   # predicate

        blank = obj.class == RDF::Node  # blank object node?                                # object node
        obj = index[obj] ||= blank ? {} : {'uri' => obj.to_s} if blank || Identifiable.member?(obj.class)

        index[s] ||= subj.node? ? {} : {'uri' => s} # subject
        index[s][p] ||= []                          # predicate
        index[s][p].push obj}                       # object

      index # output data-structure, indexed on node identity
    end
  end

end
