#!/usr/bin/env ruby
require 'async/dns'
require_relative '../index'

Host = ENV['HOST'] || '127.0.0.1'
Port = ENV['PORT'] || 53

Unfiltered = ENV.has_key? 'UNFILTERED'

class FilteredServer < Async::DNS::Server

  Seen = {}

  Log = -> name, color, v6 {
    unless Seen[name]
      Seen[name] = true
      puts [Time.now.iso8601[11..15],
            v6 ? '6️' : nil,
            [color, "\e]8;;https://#{name}/\a#{name}\e]8;;\a\e[0m"].join].
             compact.join ' '
    end}

  def resolver = @resolver ||= Async::DNS::Resolver.new(Async::DNS::Endpoint.for('1.1.1.1'))

  def process(name, resource_class, transaction)
    v6 = resource_class == Resolv::DNS::Resource::IN::AAAA
    if (resource = Webize::URI ['//', name].join).deny?
      color = "\e[38;5;#{resource.deny_domain? ? 196 : 202}#{Unfiltered ? nil : ';7'}m"
      Log[name, color, v6]
      if Unfiltered
        transaction.passthrough! resolver
      else
        transaction.respond! v6 ? '::1' : Host
      end
    else
      color = name.index('www.') == 0 ? nil : "\e[38;5;51m"
      Log[name, color, v6]
      transaction.passthrough! resolver
    end
  end
end

FilteredServer.new.run
