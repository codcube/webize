#!/usr/bin/env ruby
require 'async/dns'

class FilteredServer < Async::DNS::Server
  def process(name, resource_class, transaction)
    @resolver ||= Async::DNS::Resolver.new([[:udp, '8.8.8.8', 53], [:tcp, '8.8.8.8', 53]])
    puts name,resource_class,transaction
    transaction.passthrough!(@resolver)
  end
end

server = FilteredServer.new([[:udp, '127.0.0.1', 53]])
server.run
