# coding: utf-8

# dependencies
%w(
fileutils
pathname
shellwords).map{|d|
  require d}

module Webize
  module POSIX

    # constructor - optional environment
    def self.Node uri, env=nil
      env ? Node.new(uri).env(env) : Node.new(uri)
    end

    class Node < Resource
      include MIME

      # constructor - existing environment context
      def Node uri
        POSIX::Node.new(uri).env env
      end

    end
  end
end

# components
%w(
io
names
search
stat).map{|s|
  require_relative "POSIX/#{s}.rb"}
