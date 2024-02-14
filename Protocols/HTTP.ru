require_relative '../index'

if ENV.has_key? 'UNFILTERED'
  require 'resolv'
  require 'resolv-replace'
  hosts_resolver = Resolv::Hosts.new('/etc/hosts')
  dns_resolver = Resolv::DNS.new nameserver: %w(8.8.8.8 9.9.9.9 1.1.1.1)
  Resolv::DefaultResolver.replace_resolvers([hosts_resolver, dns_resolver])
end

run Webize::HTTP
