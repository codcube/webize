require_relative '../index'
require 'async/http'

url = ARGV.pop || "http://l:2222"
endpoint = Async::HTTP::Endpoint.parse(url)

Async do |task|
	client = Async::HTTP::Client.new(endpoint)
	response = client.get("/")
	response.each do |chunk|
		$stdout.write("> #{chunk}")
	end
ensure
	response&.close
end

run Webize::HTTP
