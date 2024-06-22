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
uri url
link
canonical_url
src
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
        scan_document{|s, p, o, graph=nil|
          s = Webize::URI.new s
          o = Webize.date o if p.to_s == Date # normalize date formats
          fn.call RDF::Statement.new(s, Webize::URI.new(p), o,
                                     graph_name: Webize::URI.new(graph || [s.host ? ['https://', s.host] : nil, s.path].join))}
      end

      def scan_document &f

        scan_node = -> node {

          # subject node
          subject = if id = Identifier.find{|i| node.has_key? i} # search for identifier
                      @base.join node.delete id # identified node
                    else
                      RDF::Node.new             # blank node
                    end

          # node attributes
          node.map{|k, v|
            predicate = MetaMap[k] || k # predicate URI

            # objects
            (v.class == Array ? v : [v]).flatten.map{|object|

              # emit triple
              yield subject,
                    predicate,
                    object.class == Hash ? scan_node[object] : object
            }
          }

          subject} # return subject node to caller

        if @doc.class == Array # toplevel array to node
          puts :ARRAY, @doc
          @doc = {Contains => @doc}
        end
        yield @base, Contains, scan_node[@doc] # scan document
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
