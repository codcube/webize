# coding: utf-8

# external dependencies
%w(fileutils pathname shellwords).map{|d|
  require d}

# internal components
%w(io names search).map{|s|
  require_relative "POSIX/${s}.rb"}

module Webize
  module POSIX

    def self.Node uri, env=nil
      env ? Node.new(uri).env(env) : Node.new(uri)
    end

    class Node < Resource
      include MIME

      def Node uri
        POSIX::Node.new(uri).env env
      end

    end
  end
end
