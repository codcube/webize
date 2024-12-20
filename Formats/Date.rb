%w(chronic date icalendar).map{|_| require _}

module Webize
  module HTML
    class Property

      Markup[Date] = :date

      def date dates
        dates.map{|d|
          d = d.to_s
          [{_: :a,
            class: :date,
            c: d,
            href: '/' + d[0..13].gsub(/[-T:]/,'/') + '*'},
           ' ']}
      end
    end

    class Reader

      DateAttr = %w(
data-time
data-timestamp
data-utc
date
datetime
time
timestamp
unixtime
data-content
title)

    end
  end

  def self.date d
    return unless d
    d = d.to_s
    return nil if d.empty?
    if d.match? /^\d+$/
      Time.at d.to_i        # UNIX time
    else
      Time.parse d          # stdlib parse
    end.utc.iso8601
  rescue
    if c = Chronic.parse(d) # Chronic parse
      c.utc.iso8601
    else
      Console.logger.debug "failed to parse time: #{d}"
      d
    end
  end

  module Calendar
    class Format < RDF::Format
      content_type 'text/calendar', :extension => :ics
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @options = options
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = RDF::URI(options[:base_uri] || '#textfile')
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
        calendar_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, RDF::URI(p), o,
                                     :graph_name => @subject)}
      end

      def calendar_triples
        Icalendar::Calendar.parse(@doc).map{|cal|
          cal.events.map{|event|
            subject = event.url || ('#event' + Digest::SHA2.hexdigest(rand.to_s))
            yield subject, Date, event.dtstart
            yield subject, Title, event.summary
            yield subject, Abstract, CGI.escapeHTML(event.description)
            yield subject, '#geo', event.geo if event.geo
            yield subject, '#location', event.location if event.location
          }}
      end
    end
  end
end
