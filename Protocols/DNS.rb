#!/usr/bin/env ruby
require 'async/dns'

class FilteredServer < Async::DNS::Server
  def process(name, resource_class, transaction)
    @resolver ||= Async::DNS::Resolver.new([#[:udp, '1.1.1.1', 53],
                                            #[:tcp, '1.1.1.1', 53],
                                            #[:udp, '8.8.8.8', 53],
                                            #[:tcp, '8.8.8.8', 53],
                                            [:udp, '2001:4860:4860::8888', 53],
                                            [:udp, '2001:4860:4860::8844', 53],
                                            [:udp, '2606:4700:4700::1111', 53],
                                            [:udp, '2606:4700:4700::1001', 53],])
    #transaction.respond!("1.2.3.4")
    puts name.class,name
    transaction.passthrough!(@resolver)
  end
end

server = FilteredServer.new([#[:udp, '127.0.0.1', 53],
                             #[:tcp, '127.0.0.1', 53],
                             [:udp, '::1', 53],
                             [:tcp, '::1', 53]])
server.run
