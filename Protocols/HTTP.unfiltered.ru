require_relative '../index'

# if we used the system resolver we'd end up back at ourself, so use some upstream servers
require 'resolv'
require 'resolv-replace'
hosts_resolver = Resolv::Hosts.new('/etc/hosts')
dns_resolver = Resolv::DNS.new nameserver: %w(8.8.8.8 9.9.9.9 1.1.1.1)
Resolv::DefaultResolver.replace_resolvers([hosts_resolver, dns_resolver])

run Webize::HTTP
