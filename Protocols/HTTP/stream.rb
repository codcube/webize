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

        #stream.each do |message|
        #  puts message
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
        barrier = Async::Barrier.new                   # concurrency limits
        semaphore = Async::Semaphore.new 24, parent: barrier
        uris.map{|uri|                                 # resource(s)
          semaphore.async{
            node = Node uri                            # locator (HTTP::Node)
            status, header, _ = node.fetch do |graphs| # response data (RDF::Repository)
              graphs.index(env,node) do |graph|        # persist response graph(s)
                stream <<                              # Graph -> JSON -> HTML -> client (SSE)
                  "data: #{HTML.render HTML.markup(JSON.fromGraph(graph).values, env)}\n\n"
                syndicate graph                        # graph -> global/firehose-update clients
              end
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
