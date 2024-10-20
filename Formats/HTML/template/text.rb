module Webize
  module HTML
    class Node

      # page breaks

      def br(node) = inlineResource node, :br
      def hr(node) = inlineResource node, :hr

      # headings

      def h1(node) = identifiedResource node, :h1
      def h2(node) = identifiedResource node, :h2
      def h3(node) = identifiedResource node, :h3
      def h4(node) = identifiedResource node, :h4
      def h5(node) = identifiedResource node, :h5
      def h6(node) = identifiedResource node, :h6

      # text elements
      def abbr(node) = inlineResource node, :abbr
      def acronym(node) = inlineResource node, :acronym
      def b(node) = inlineResource node, :b
      def blockquote(node) = identifiedResource node, :blockquote
      def cite(node) = identifiedResource node, :cite
      def em(node) = inlineResource node, :em
      def i(node) = inlineResource node, :i
      def p(node) = identifiedResource node, :p
      def script(code) = resource code, :code
      def span(node) = inlineResource node, :span
      def strong(node) = inlineResource node, :strong
      def sup(node) = inlineResource node, :sup
      def u(node) = inlineResource node, :u

      def pre(content) = unlabeledResource content, :pre
      def code(content) = bareResource content, :code

      def comment c
        {_: :span, class: :comment,
         c: ['&lt;!--',
             c[Contains].map{|content|
               HTML.markup content, env},
             '--&gt;']}
      end

      # hypertext anchor
      def a anchor
        return inlineResource anchor, :a unless anchor.has_key? Link

        anchor.delete XHV + 'target' # strip upstream link behaviour

        if id = anchor['uri'] # identified anchor
          anchor_id = Webize::Resource(id, env).local_id
        end

        anchor[Link].map{|l|
          next unless l.class == Hash

          u = Webize::Resource l['uri'], env # URI

          {_: :a, href: u.href,              # reference resolved for current context

           class: u.host == host ? 'local' : 'global', # local or global link styling

           c: [anchor[Contains]&.map{|content|         # inner text
                 HTML.markup content, env},

               {_: :span, class: :uri,                 # identifier
                c: [u.host,
                    (CGI.escapeHTML(u.path) if u.path)]},

               keyval(anchor.merge(u.query_hash),
                      inline: true,
                      skip: ['uri', Contains, Link, Type])]}.
            update(id ? (id = nil; {id: anchor_id}) : {})} # show ID on first link only if multiple targets
      end

    end
  end
end
