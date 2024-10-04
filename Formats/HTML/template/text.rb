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
      def sup(node) = bareResource node, :sup
      def u(node) = bareResource node, :u

      # hypertext anchor
      def a anchor
        return resource anchor, :a unless anchor.has_key? Link

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
                    (CGI.escapeHTML(u.path) if u.path),
                    u.query_hash.map{|k,v|
                      ['<br>',
                       {_: :span, class: :key,
                        c: (CGI.escapeHTML k if k)},
                       (CGI.escapeHTML v.to_s if v)]}]},

               keyval(anchor,
                      inline: true,
                      skip: ['uri', Contains, Link, Title, Type])
              ]}.
            update(id ? (id = nil; {id: anchor_id}) : {})} # show ID on first link only if multiple targets
      end

    end
  end
end
