#!/usr/bin/env ruby
require 'async/dns'
require_relative '../index'

class Webize::DNS < Async::DNS::Server

  Seen = {} # hosts we've encountered in current run

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
      color = "\e[38;5;#{resource.deny_domain? ? 196 : 202};7m"
      Log[name, color, v6]
      transaction.respond! v6 ? '::1' : '127.0.0.1'
    else
      color = name.index('www.') == 0 ? nil : "\e[38;5;51m"
      Log[name, color, v6]
      transaction.passthrough! resolver
    end
  end
end
