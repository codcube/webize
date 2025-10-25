#!/usr/bin/env ruby
require 'async/dns'
require_relative '../index'

class Webize::DNS < Async::DNS::Server

  Seen = {} # hosts we've encountered in current run

  Log = -> resource {
    unless Seen[resource.host]
      Seen[resource.host] = true # mark as visited

      # link resource to timeline graph
      Webize::Graph << RDF::Statement.new(resource, RDF::URI(Date), Time.now.iso8601, graph_name: RDF::URI(Time.now.utc.strftime '/%Y/%m/%d/%H/'))

      # logging
      color = if resource.deny?
                "\e[38;5;#{resource.deny_domain? ? 196 : 202};7m"
              else
                "\e[38;5;51m"
              end
      puts [Time.now.iso8601[11..15],
            [color, "\e]8;;https://#{resource.host}/\a#{resource.host}\e]8;;\a\e[0m"].join].
             compact.join ' '
    end}

  def resolver = @resolver ||= Async::DNS::Resolver.new(Async::DNS::Endpoint.for('1.1.1.1'))

  def process(name, resource_class, transaction)
    resource = Webize::URI ['//', name].join # host URI
    Log[resource]                            # log request
                                             # response
    if resource.deny?
      # BLOCK
      # respond with IPv4/6 localhost address of proxy/tunnel listeners for filtered egress
      # note we previously supported ENV config of proxy address but this wasn't used because browsers/clients offer this option scoped to themselves where it won't by neccessity apply to every program's requests. if you want global proxy settings without requiring client config, the feature could be added back here
      transaction.respond! resource_class == Resolv::DNS::Resource::IN::AAAA ? '::1' : '127.0.0.1'
    else
      # ALLOW
      # pass through DNS (+ therefore HTTP) requests to origin server
      transaction.passthrough! resolver
    end
  end
end
