module Webize
  class HTTP::Node

    Subscribers = Set.new # client list for updates

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
