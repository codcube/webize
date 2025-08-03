module Webize
  class HTTP::Node

    def streaming? = env['HTTP_ACCEPT'].include? 'text/event-stream'

    def multiGET uris
      body = proc do |stream|
        barrier = Async::Barrier.new # limit concurrency
        semaphore = Async::Semaphore.new 24, parent: barrier
        uris.map{|u|                 # URIs to fetch
          semaphore.async{
            node = Node u            # instantiate HTTP::Node resource
            node.
              fetch(thru: false).        # fetch to in-memory RDF::Repository
              index(env,node) do |graph| # index graph and notify caller of update(s)
              stream << "data: #{u} #{graph.name} #{Time.now}\n\n"
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
