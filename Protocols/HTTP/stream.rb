module Webize
  class URI

    def streamable? = path == '/' || extname == '.u'
  end
  class HTTP::Node

    Writers = Set.new # data sinks get a writer
    Readers = Set.new # data sources get a reader

    def firehose
      body = proc do |stream|
        Readers << reader = ::JSON::LD::Reader.new(stream, stream: true)
        Writers << writer = ::JSON::LD::Writer.new(stream)
        puts "firehose:", stream, reader, writer
        reader.each_statement do |s|
          puts s
        end
      rescue => error
      ensure
        Readers.delete reader
        Writers.delete writer
	      stream.close(error)
      end
      [200, {'content-type' => 'text/event-stream'}, body]
    end

    def multiGET uris
      body = proc do |stream|
        barrier = Async::Barrier.new     # limit concurrency
        semaphore = Async::Semaphore.new 24, parent: barrier
        uris.map{|uri|                   # resource list
          semaphore.async{
            node = Node uri              # resource (HTTP::Node)
            node.fetch(thru: false).     # resource -> graph (RDF::Repository)
              index(env,node) do |graph| # graph -> local cache/index
              stream <<                  # graph HTML representation -> SSE client
                "data: #{HTML.render HTML.markup(JSON.fromGraph(graph).values, env)}\n\n"
              syndicate graph            # graph -> firehose/global-updates client(s)
            end
          }}
        barrier.wait
      rescue => error
      ensure
	      stream.close(error)
      end
      [200, {'content-type' => 'text/event-stream'}, body]
    end

    def streaming? = env['HTTP_ACCEPT'].include? 'text/event-stream'

    def syndicate(graph) = graph.each_statement do |s|
      Writers.map do |w|
        w.stream_statement s
      end
    end

  end
end
