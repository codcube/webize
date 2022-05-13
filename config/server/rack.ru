require_relative '../index' # webize library

#require 'resolv'            # DNS resolver
#require 'resolv-replace'
#hosts_resolver = Resolv::Hosts.new('/etc/hosts')
#dns_resolver = Resolv::DNS.new nameserver: %w(8.8.8.8 9.9.9.9 1.1.1.1)
#Resolv::DefaultResolver.replace_resolvers([hosts_resolver, dns_resolver])

run WebResource::HTTP
