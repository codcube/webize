#!/usr/bin/env ruby
require 'async/dns'
require_relative '../index'

class FilteredServer < Async::DNS::Server

  DefaultAddr = ENV['ADDR'] || '127.0.0.1'

  Log = -> name, color {
    v6 = resource_class == Resolv::DNS::Resource::IN::AAAA
    puts [Time.now.iso8601[11..15], v6 ? '6️⃣' : nil, [color, "\e]8;;https://#{name}/\a#{name}\e]8;;\a\e[0m"].join].compact.join ' '
  }

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

    resource = Webize::URI(['//', name].join)

    if resource.deny?
      color = "\e[38;5;#{resource.deny_domain? ? 196 : 202};7m"
      Log[name, resource_class, color]
      transaction.respond! v6 ? '::1' : DefaultAddr
    else
      color = name.index('www.') == 0 ? nil : "\e[38;5;51m"
      Log[name, resource_class, color]
      transaction.passthrough! @resolver
    end
  end
end

## Listener

# if binding isn't allowed, the minimalist solution is:

# 1) use a high-port resolver specification in /etc/resolv.conf or your system resolver settings

# or you can enable low-port binding on a linux-compatible OS by running:

# 2) sudo setcap 'cap_net_bind_service=+ep' /usr/bin/ruby

# or change the below port to high (>1024) and,

# 3) redirect port 53 to say 1053 or 5300 via kernel tables by running the <../low_ports> script, or
# 4) redirect traffic in userspace with a 'sudo socat' instantiation

server = FilteredServer.new([[:udp, '127.0.0.1', 53],
                             [:tcp, '127.0.0.1', 53],
                             [:udp, '::1', 53],
                             [:tcp, '::1', 53]])
server.run
