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
    def self.scan v, &y
      case v.class.to_s
      when 'Hash'
        yield v
        v.values.map{|_v| scan _v, &y }
      when 'Array'
        v.map{|_v| scan _v, &y }
      end
    end

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

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @json = ::JSON.parse(input.respond_to?(:read) ? input.read : input) rescue (logger.debug ['JSON parse failure in: ', @base].join; {})
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
        scanContent{|s, p, o, graph=nil|
          s = Webize::URI.new s
          o = Webize.date o if p.to_s == Date # normalize date formats
          fn.call RDF::Statement.new(s, Webize::URI.new(p), o,
                                     graph_name: Webize::URI.new(graph || [s.host ? ['https://', s.host] : nil, s.path].join))}
      end

      def JSONfeed
        @json['items'].map{|item|
          s = @base.join(item['url'] || item['id'])
          yield s, Type, RDF::URI(Post)
          item.map{|p, o|
            case p
            when 'attachments'
              o.map{|a|
                attachment = @base.join(a['url']); attachment.path ||= '/'
                type = case File.extname attachment.path
                       when /m4a|mp3|ogg|opus/i
                         Audio
                       when /mkv|mp4|webm/i
                         Video
                       else
                         Link
                       end
                yield s, type, attachment}
              drop = true
            when 'author'
              yield s, Creator, o['name']
              yield s, Creator, RDF::URI(o['url'])
              drop = true
            when 'content_text'
              p = Contains
              o = CGI.escapeHTML o
            end
            yield s, p, o unless drop}} if @json['items'] && @json['items'].respond_to?(:map)
      end

      def scanContent &f
        if hostTriples = Triplr[@base.host]
          @base.send hostTriples, @json, &f
        else
          JSON.scan(@json){|h|
            if s = h['expanded_url']||h['uri']||h['url']||h['link']||h['canonical_url']||h['src']|| # URL attribute
                   ((id = h['id'] || h['ID'] || h['_id'] || h['id_str']) && ['#', id].join)         # id attribute
              s = Webize::URI.new @base.join s                                                      # subject URI. TODO return to caller for triple pointing to inner resource
              if s.parts[0] == 'users'
                host = RDF::URI('https://' + s.host)
                yield s, Creator, host.join(s.parts[0..1].join('/'))
                yield s, To, host
              end
              h.map{|p, v|
                unless %w(_id id id_str uri).member? p
                  (v.class == Array ? v : [v]).map{|o|
                    unless [Hash, NilClass].member?(o.class) || (o.class == String && o.empty?)     # each non-nil terminal value
                      o = @base.join o if o.class == String && o.match?(/^(http|\/)\S+$/)           # resolve URI
                      p = MetaMap[p] if MetaMap.has_key? p
                      unless p == :drop
                        logger.warn ["no URI for JSON key \e[7m", p, "\e[0m ", o].join unless p.match? /^https?:/
                        yield s, p, o
                      end
                    end
                  }
                end
              }
            end
          }
        end
      end
    end

    # Graph -> Tree {subject => {predicate => [object]}}
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

      inlined.map{|n| tree.delete n} # sweep inlined nodes from toplevel index
      tree                           # tree
    end
  end

end
