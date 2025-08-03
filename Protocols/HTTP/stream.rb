module Webize
  class HTTP::Node

    def streaming? = env['HTTP_ACCEPT'].include? 'text/event-stream'

    def multiGET uris
      puts env
      body = proc do |stream|
        barrier = Async::Barrier.new     # limit concurrency
        semaphore = Async::Semaphore.new 24, parent: barrier
        uris.map{|uri|                   # resources to GET
          semaphore.async{
            node = Node uri              # instantiate HTTP::Node
            node.fetch(thru: false).     # fetch resource to RDF::Repository
              index(env,node) do |graph| # cache and index graph-data
                                         # notify caller of update(s)
              stream << "data: #{HTML.markup JSON.fromGraph(graph)[graph.name.to_s], env}\n\n"
            end
          }}
        barrier.wait
      rescue => error
      ensure
	      stream.close(error)
      end
      [200, {'content-type' => 'text/event-stream'}, body]
    end

  end
end
