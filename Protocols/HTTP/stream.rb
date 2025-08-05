module Webize
  class URI

    def streamable? = path == '/' || extname == '.u'
  end
  class HTTP::Node

    Subscribers = Set.new # runtime client list
    #Node::Subscribers.each{|stream|stream << "data: #{uri}\n\n"} # update log subscribers

    def firehose
      body = proc do |stream|
        Subscribers << stream
        while true
          stream << "data: timestamp #{Time.now}<br>\n\n"
          sleep 3600
        end
      rescue => error
      ensure
        Subscribers.delete stream
	      stream.close(error)
      end
      [200, {'content-type' => 'text/event-stream'}, body]
    end

    def streaming? = env['HTTP_ACCEPT'].include? 'text/event-stream'

    def multiGET uris
      body = proc do |stream|
        barrier = Async::Barrier.new     # limit concurrency
        semaphore = Async::Semaphore.new 24, parent: barrier
        uris.map{|uri|                   # resources to GET
          semaphore.async{
            node = Node uri              # instantiate HTTP::Node
            node.fetch(thru: false).     # fetch resource to RDF::Repository
              index(env,node) do |graph| # cache and index graph-data
                                         # notify caller of update(s)
              stream << "data: #{HTML.render HTML.markup(JSON.fromGraph(graph).values, env)}\n\n"
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
