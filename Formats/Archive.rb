# coding: utf-8
module Webize
  module ArchiveFile
    class Format < RDF::Format
      content_type 'application/x-tar',
                   aliases: %w(
                   application/x-bzip2;q=0.8
                   application/x-gzip;q=0.8
                   application/x-xz;q=0.8
                   application/gzip;q=0.8
                   application/zip;q=0.8
),
                   extensions: [:gz,:tar]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = (options[:base_uri] || '#zip').R
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
        archive_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def archive_triples
      end
    end
  end
end
class WebResource

  NoSummary = [Image, Schema+'ItemList', SIOC+'MicroPost'].map &:R # no summary for these resource-types

  # file -> 🐢 file w/ extracts/summary for archive/container indexes etc
  def preview
    hash = Digest::SHA2.hexdigest uri
    file = [:cache,:overview,hash[0..1],hash[2..-1]+'.🐢'].join '/'  # summary path
    summary = file.R env                                             # summary resource
    return summary if File.exist?(file) && File.mtime(file) >= mtime # cached summary up to date

    fullGraph = RDF::Repository.new                                  # full graph
    miniGraph = RDF::Repository.new                                  # summary graph

    loadRDF graph: fullGraph                                         # load graph
    saveRDF fullGraph if basename.index('msg.') == 0                 # cache RDF extracted from nonRDF
    treeFromGraph(fullGraph).map{|subject, resource|                 # resources to summarize
      subject = subject.R                                            # subject resource
      full = (resource[Type]||[]).find{|t| NoSummary.member? t}      # resource-types retaining full content
      predicates = [Abstract, Audio, Creator, Date, Image, LDP+'contains', DC+'identifier', Title, To, Type, Video, Schema+'itemListElement']
      predicates.push Content if full                                # main content sometimes included in preview
      predicates.push Link unless subject.host                       # include untyped links in local content
      predicates.map{|predicate|                                     # summary-statement predicate
        if o = resource[predicate]
          (o.class == Array ? o : [o]).map{|o|                       # summary-statement object(s)
            if o.class == Hash                                       # blanknode object
              object = RDF::Node.new
              o.map{|p,objets|
                objets.map{|objet|
                  miniGraph << RDF::Statement.new(object, p.R, objet)}} # bnode triples
            else
              object = o
            end
            miniGraph << RDF::Statement.new(subject,predicate.R,object)} # summary-statement triple
        end} if [Image,Abstract,Title,Link,Video].find{|p|resource.has_key? p} || full} # if summary-data exists

    summary.writeFile miniGraph.dump(:turtle,base_uri: self,standard_prefixes: true) # cache summary
    summary                                                          # return summary
  end

end
