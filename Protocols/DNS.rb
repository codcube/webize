#!/usr/bin/env ruby
require 'async/dns'
require_relative '../index'

class FilteredServer < Async::DNS::Server

  DefaultAddr = ENV['ADDR'] || '127.0.0.1'
  Seen = {}

  Log = -> name, color, v6 {
    unless Seen[name]
      Seen[name] = true
      puts [Time.now.iso8601[11..15],
            v6 ? '6️⃣' : nil,
            [color, "\e]8;;https://#{name}/\a#{name}\e]8;;\a\e[0m"].join].
             compact.join ' '
    end}

  def process(name, resource_class, transaction)

    # TODO find any upstream/ISP-provided resolvers in /etc/resolv.conf before setting that to point to us
    @resolver ||= Async::DNS::Resolver.new([
                                             ## Cloudflare
                                             # ipv4
                                             [:udp, '1.1.1.1', 53],
                                             [:tcp, '1.1.1.1', 53],
                                             [:udp, '1.0.0.1', 53],
                                             [:tcp, '1.0.0.1', 53],
                                             # ipv6
                                             [:udp, '2606:4700:4700::1111', 53],
                                             [:tcp, '2606:4700:4700::1111', 53],
                                             [:udp, '2606:4700:4700::1001', 53],
                                             [:tcp, '2606:4700:4700::1001', 53],

                                             ## Google
                                             # ipv4
                                             [:udp, '8.8.8.8', 53],
                                             [:tcp, '8.8.8.8', 53],
                                             [:udp, '8.8.4.4', 53],
                                             [:tcp, '8.8.4.4', 53],
                                             # ipv6
                                             [:udp, '2001:4860:4860::8888', 53],
                                             [:tcp, '2001:4860:4860::8888', 53],
                                             [:udp, '2001:4860:4860::8844', 53],
                                             [:tcp, '2001:4860:4860::8844', 53],

                                           ])

    v6 = resource_class == Resolv::DNS::Resource::IN::AAAA
    resource = Webize::URI(['//', name].join)

    if resource.deny?
      color = "\e[38;5;#{resource.deny_domain? ? 196 : 202};7m"
      Log[name, color, v6]
      if ENV.has_key? 'LEAKY'
        transaction.passthrough! @resolver
      else
        transaction.respond! v6 ? '::1' : DefaultAddr
      end
    else
      color = name.index('www.') == 0 ? nil : "\e[38;5;51m"
      Log[name, color, v6]
      transaction.passthrough! @resolver
    end
  end
end

# if binding port 53 is not available:

# enable low-port binding on linux-compatible OS,

# 1) sudo setcap 'cap_net_bind_service=+ep' /usr/bin/ruby

# move the priveleged-port start point,

# 2) sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80

# or change the binding port to high (>1024) and,

# 3) use a high-port resolver specification in /etc/resolv.conf or other system resolver settings if supported:
# echo nameserver 127.0.0.1:1053 | sudo tee /etc/resolv.conf

# 4) redirect port 53 to a high port in kernel routing tables with the <../low_ports> script

# 5) redirect traffic in userspace with netcat/socat

server = FilteredServer.new([[:udp, '127.0.0.1', 53],
                             [:tcp, '127.0.0.1', 53],
                             [:udp, '::1', 53],
                             [:tcp, '::1', 53]])
server.run
