module Webize
  class HTTP::Node

    def streaming? = env['HTTP_ACCEPT'].include? 'text/event-stream'

    def multiGET uris
      body = proc do |stream|
        barrier = Async::Barrier.new # limit concurrency
        semaphore = Async::Semaphore.new 24, parent: barrier
        uris.map{|u|                 # URIs to fetch
          semaphore.async{
            repo = Node(u).fetch thru: false
            stream << "data: #{u} #{repo.subjects.join ' '} #{Time.now}\n\n"
          }}
        barrier wait
      rescue => error
      ensure
	      stream.close(error)
      end
      [200, {'content-type' => 'text/event-stream'}, body]
    end

  end
end
