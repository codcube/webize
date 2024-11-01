module Webize
  module HTML
    class Node

      # page breaks

      def br(node) = inlineResource node, :br
      def hr(node) = inlineResource node, :hr

      # headings

      def h1(node) = inlineResource node, :h1
      def h2(node) = inlineResource node, :h2
      def h3(node) = inlineResource node, :h3
      def h4(node) = inlineResource node, :h4
      def h5(node) = inlineResource node, :h5
      def h6(node) = inlineResource node, :h6

      # text elements
      def abbr(node) = inlineResource node, :abbr
      def acronym(node) = inlineResource node, :acronym
      def b(node) = inlineResource node, :b
      def blockquote(node) = identifiedResource node, :blockquote
      def cite(node) = identifiedResource node, :cite
      def em(node) = inlineResource node, :em
      def i(node) = inlineResource node, :i
      def p(node) = inlineResource node, :p
      def script(code) = resource code, :code
      def span(node) = inlineResource node, :span
      def strong(node) = inlineResource node, :strong
      def sup(node) = inlineResource node, :sup
      def u(node) = inlineResource node, :u

      def pre(content) = blockResource content, :pre
      def code(content) = blockResource content, :code

      def comment c
        {_: :span, class: :comment,
         c: ['&lt;!--',
             c[Contains].map{|content|
               HTML.markup content, env},
             '--&gt;']}
      end

      # hypertext anchor
      def a anchor
        anchor.delete XHV + 'target' # strip upstream link behaviours

        if id = anchor['uri']        # resolve identifier
          anchor_id = Webize::Resource(id, env).local_id
        end

        anchor[Link]&.map{|l| # we allow multiple targets - each renders as its own <a>
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
                      skip: ['uri', Contains, Link, Type, To])]}.
            update(id ? (id = nil; {id: anchor_id}) : {})} # attach id to first link
      end

    end
  end
end
