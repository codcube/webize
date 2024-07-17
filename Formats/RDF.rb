# coding: utf-8

# add 🐢 suffix map for turtle format
RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl]

module Webize

  # Ruby classes capable of representing an RDF resource with an identifier
  Identifiable = [RDF::URI,
                  Webize::URI,
                  Webize::Resource,
                  Webize::POSIX::Node,
                 ]

  module Graph
    # namespace for util methods for RDF Graph/Repository instances
  end

end
