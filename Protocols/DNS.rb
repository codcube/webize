#!/usr/bin/env ruby
require 'async/dns'
require_relative '../index'

class FilteredServer < Async::DNS::Server

  DefaultAddr = ENV['ADDR'] || '127.0.0.1'

  def process(name, resource_class, transaction)

    # TODO find any upstream/ISP-provided resolvers in /etc/resolv.conf before setting that to point to us
    @resolver ||= Async::DNS::Resolver.new([
                                             # cloudflare
                                             [:udp, '1.1.1.1', 53],
                                             [:tcp, '1.1.1.1', 53],
                                             [:udp, '2606:4700:4700::1111', 53],
                                             [:tcp, '2606:4700:4700::1111', 53],
                                             [:udp, '2606:4700:4700::1001', 53],
                                             [:tcp, '2606:4700:4700::1001', 53],

                                             # google
                                             [:udp, '8.8.8.8', 53],
                                             [:tcp, '8.8.8.8', 53],
                                             [:udp, '2001:4860:4860::8888', 53],
                                             [:tcp, '2001:4860:4860::8888', 53],
                                             [:udp, '2001:4860:4860::8844', 53],
                                             [:tcp, '2001:4860:4860::8844', 53],
                                           ])

    v6 = resource_class == Resolv::DNS::Resource::IN::AAAA
    resource = Webize::URI(['//', name].join)

    if resource.deny?
      color = "\e[38;5;#{resource.deny_domain? ? 196 : 202};7m"
      puts [Time.now.iso8601[11..15], v6 ? '6️⃣' : nil, [color, "\e]8;;https://#{name}/\a#{name}\e]8;;\a\e[0m"].join].join ' '
      addr = v6 ? '::1' : DefaultAddr
      transaction.respond! addr
    else
      color = name.index('www.') == 0 ? nil : "\e[38;5;51m"
      puts [Time.now.iso8601[11..15], v6 ? '6️⃣' : nil, [color, "\e]8;;https://#{name}/\a#{name}\e]8;;\a\e[0m"].join].join ' '
      transaction.passthrough! @resolver
    end
  end
end

# if binding isn't allowed, you can enable it by running on (linux-compatible) OS:
#  sudo setcap 'cap_net_bind_service=+ep' /usr/bin/ruby
# or change the port to a high (>1024) and,
# redirect 53 to say 1053 or 5300 via the kernel tables by running the ../low_ports script, or redirect the traffic via a 'sudo socat' listener, or try a direct high-port specification in /etc/resolv.conf or your system resolver settings
server = FilteredServer.new([[:udp, '127.0.0.1', 53],
                             [:tcp, '127.0.0.1', 53],
                             [:udp, '::1', 53],
                             [:tcp, '::1', 53]])
server.run
