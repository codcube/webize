# coding: utf-8

# dependencies
%w(async async/barrier async/semaphore
brotli
cgi
digest/sha2
open-uri
rack
resolv).map{|d|
  require d}

module Webize
  module HTTP

    Args = Webize.configList 'HTTP/arguments'            # permitted query arguments
    Methods = Webize.configList 'HTTP/methods'           # permitted HTTP methods
    ActionIcon = Webize.configHash 'style/icons/action'  # HTTP method -> char
    StatusIcon = Webize.configHash 'style/icons/status'  # status code (string) -> char
    StatusIcon.keys.map{|s|                              # status code (int) -> char
      StatusIcon[s.to_i] = StatusIcon[s]}
    Redirector = {}                                      # redirection cache
    Referer = {}                                         # referer cache

    # constructor
    def self.Node(uri, env) = Node.new(uri).env env

    class Node < Resource
      include MIME

      # constructor - existing environment context
      def Node(uri) = HTTP::Node.new(uri).env env

    end
  end
end

# components
%w(
metadata
method
proxy
rack
read
write
).map{|s|
  require_relative "HTTP/#{s}.rb"}
