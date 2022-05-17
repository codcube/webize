require 'json'
module Webize
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
                   extensions: [:json, :webmanifest],
                   aliases: %w(
                   text/json
                   application/manifest+json;q=0.8
                   application/vnd.imgur.v1+json;q=0.1)
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R
        @json = ::JSON.parse(input.respond_to?(:read) ? input.read : input) rescue (puts input.to_s.gsub(/\n/,' '); {})
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
          fn.call RDF::Statement.new(s.R, p.R,
                                     p == Content ? ((l = RDF::Literal o).datatype = RDF.HTML
                                                      l) : o,
                                     graph_name: graph ? graph.R : @base)}
      end

      def JSONfeed
        @json['items'].map{|item|
          s = @base.join(item['url'] || item['id'])
          yield s, Type, Post.R
          item.map{|p, o|
            case p
            when 'attachments'
              o.map{|a|
                attachment = @base.join(a['url']).R; attachment.path ||= '/'
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
              yield s, Creator, o['url'].R
              drop = true
            when 'content_text'
              p = Content
              o = CGI.escapeHTML o
            end
            yield s, p, o unless drop}} if @json['items'] && @json['items'].respond_to?(:map)
      end

      def scanContent &f
        if hostTriples = Triplr[@base.host]
          @base.send hostTriples, @json, &f
        else
          Webize::JSON.scan(@json){|h|
            if s = h['expanded_url']||h['uri']||h['url']||h['link']||h['canonical_url']||h['src']|| # URL attribute
                   ((id = h['id'] || h['ID'] || h['_id'] || h['id_str']) && ['#', id].join)         # id attribute
              s = @base.join(s).R                                                                   # subject URI. TODO return to caller for triple pointing to inner resource
              if s.parts[0] == 'users'
                host = ('https://' + s.host).R
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
                        puts [p, o].join "\t " unless p.match? /^https?:/
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
  end
end
class WebResource

  # RDF from JSON embedded in HTML
  def JSONembed doc, pattern, &b
    doc.css('script').map{|script|
      script.inner_text.lines.grep(pattern).map{|line|
        Webize::JSON::Reader.new(line.sub(/^[^{]+/,'').chomp.sub(/};.*/,'}'), base_uri: self).scanContent &b}}
  end
end
