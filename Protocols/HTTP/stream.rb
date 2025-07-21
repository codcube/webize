module Webize
  class HTTP::Node

    def streaming? = env['HTTP_ACCEPT'].include? 'text/event-stream'

    def fetchRemotes nodes
      barrier = Async::Barrier.new # limit concurrency
#      return updateStream if 

      semaphore = Async::Semaphore.new(24, parent: barrier)

      repos = []                   # repository references

      nodes.map{|n|
        semaphore.async{           # fetch URI -> repository
          repos << (Node(n).fetch thru: false)}}

      barrier.wait
      respond repos                # repositories -> HTTP response
    end

    def updateStream
      body = proc do |stream|
        Subscribers << stream
	while true
	  stream << "data: The time is #{Time.now}\n\n"
	  sleep 3600
	end
      rescue => error
      ensure
        Subscribers.delete stream
	stream.close(error)
      end

      [200, {'content-type' => 'text/event-stream'}, body]
    end

  end
end
