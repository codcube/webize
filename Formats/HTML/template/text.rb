module Webize
  module HTML
    class Node

      # page breaks

      def br(node) = inlineResource node, :br
      def hr(node) = inlineResource node, :hr

      # headings

      def h1(node) = resource node, :h1
      def h2(node) = resource node, :h2
      def h3(node) = resource node, :h3
      def h4(node) = resource node, :h4
      def h5(node) = resource node, :h5
      def h6(node) = resource node, :h6

      # text elements

      def b(node) = inlineResource node, :b
      def blockquote(node) = identifiedResource node, :blockquote
      def cite(node) = identifiedResource node, :cite
      def em(node) = inlineResource node, :em
      def i(node) = inlineResource node, :i
      def p(node) = identifiedResource node, :p
      def span(node) = inlineResource node, :span
      def strong(node) = inlineResource node, :strong
      def sup(node) = inlineResource node, :sup
      def u(node) = inlineResource node, :u

      # hypertext anchor
      def a anchor
        return inlineResource anchor, :a unless anchor.has_key? Link

        if id = anchor['uri'] # identified anchor
          anchor_id = Webize::Resource(id, env).local_id
        end

        anchor[Link].map{|l|
          next unless l.class == Hash

          u = Webize::Resource l['uri'], env # URI

          {_: :a, href: u.href,              # reference resolved for current context

           class: u.host == host ? 'local' : 'global', # local or global link styling

           c: [[Title, Contains].map{|text|            # text attributes
                 next unless anchor.has_key? text

                 anchor[text].map{|content|            # inner text
                   HTML.markup content, env}},

               {_: :span, class: :uri,
                c: [u.host,
                    (CGI.escapeHTML(u.path) if u.path)]},

               keyval(anchor.merge(u.query_hash),
                      inline: true,
                      skip: ['uri', Contains, Link, Title, Type])]}.
            update(id ? (id = nil; {id: anchor_id}) : {})} # show ID on first link only if multiple targets
      end

    end
  end
end
