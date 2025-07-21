module Webize
  class HTTP::Node

    def streaming? = env['HTTP_ACCEPT'].include? 'text/event-stream'

    def multiGET uris
      semaphore = Async::Semaphore.new 24
      body = proc do |stream|
        uris.map{|u|
          semaphore.async{
            repo = Node(u).fetch thru: false
            stream << "data: #{u} #{Time.now}\n\n"
          }}
      rescue => error
      ensure
	      stream.close(error)
      end
      [200, {'content-type' => 'text/event-stream'}, body]
    end

  end
end
