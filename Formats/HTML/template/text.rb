module Webize
  module HTML
    class Node

      # page breaks

      def br(node) = bareResource node, :br
      def hr(node) = bareResource node, :hr

      # headings

      def h1(node) = resource node, :h1
      def h2(node) = resource node, :h2
      def h3(node) = resource node, :h3
      def h4(node) = resource node, :h4
      def h5(node) = resource node, :h5
      def h6(node) = resource node, :h6

      # text elements

      def b(node) = bareResource node, :b
      def blockquote(node) = identifiedResource node, :blockquote
      def cite(node) = identifiedResource node, :cite
      def em(node) = bareResource node, :em
      def p(node) = identifiedResource node, :p
      def span(node) = bareResource node, :span
      def strong(node) = bareResource node, :strong

      # hypertext anchor
      def a anchor
        [if anchor.has_key? Link
         anchor[Link].map{|l| next unless l.class == Hash

           u = Webize::URI l['uri']

           {_: :a, href: u.href,
            class: u.host == host ? 'local' : 'global',
            c: [[Title, Contains].map{|t|
                  next unless anchor.has_key? t
                  anchor[t].map{|c|
                    HTML.markup c, env}},
                {_: :span, class: :uri,
                 c: CGI.escapeHTML(u.to_s.sub /^https?:..(www.)?/, '')}]}}
         end,

         keyval(anchor,
                skip: ['uri', Contains, Link, Title, Type])]
      end

    end
  end
end
