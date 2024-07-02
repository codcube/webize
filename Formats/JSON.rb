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
        @doc = ::JSON.parse(input.respond_to?(:read) ? input.read : input) rescue (logger.debug ['JSON parse failure in: ', @base].join; {})
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

        subject = if id = Identifier.find{|i| node.has_key? i}  # search for identifier
                    @base.join node.delete id                   # subject URI
                  else
                    RDF::Node.new                               # unidentified node
                  end
        graph = Webize::URI(subject).graph unless subject.node? # graph URI

        # attributes
        node.map{|k, v|

          # predicates
          predicate = MetaMap[k] || k # map predicate URI

          unless predicate == :drop

            # warn on unmapped predicate. chatty w/ JSON-in-wild's vast array of non-URI attribute names
            unless predicate.match? HTTPURI
              logger.warn ["no URI for JSON attr \e[7m", predicate, "\e[0m "].join
            end

            # objects
            (v.class == Array ? v : [v]).flatten.map{|object|

              if object.class == String
                 if object.match? RelURI
                   object = @base.join object   # URI
                 else
#                  object = RDF::Literal object # literal
                 end
              end

              object = Webize.date object if predicate == Date # normalize date format

              # triple
              yield subject,
                    Webize::URI(predicate),
                    object.class == Hash ? scan_node(object, graph, &f) : object unless object.nil?}
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

    # Graph -> Tree
    def self.fromGraph graph
      tree = {}                         # output tree
      inlined = []                      # inlined nodes

      graph.each_triple{|subj,pred,obj| # visit graph
        s = subj.to_s                   # subject
        p = pred.to_s                   # predicate
        blank = obj.class == RDF::Node  # bnode?

        # inline objects
        if blank || (p == Contains && Resources.member?(obj.class))
          o = obj.to_s                  # object identity
          inlined.push o                # add to inline-objects list
          obj = tree[o] ||=             # dereference object, initializing and
              blank ? {} : {'uri' => o} # adding to index on first occurrence
        end

        tree[s] ||= subj.class == RDF::Node ? {} : {'uri' => s} # subject
        tree[s][p] ||= []                                       # predicate
        tree[s][p].push obj}                                    # object

      inlined.map{|n| tree.delete n} # sweep inlined nodes from index

      # output tree
      {Type => [Document],
       Contains => tree.values}
    end
  end

end
