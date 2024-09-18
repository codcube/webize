module Webize
  module HTML
    class Node

      # basic DOM nodes - parameterize generic renderer with name

      def head(node) = resource node, :head

      # list elements
      def ul(node) = resource node, :ul
      def ol(node) = resource node, :ol
      def li(node) = resource node, :li

      # headings
      def h1(node) = resource node, :h1
      def h2(node) = resource node, :h2
      def h3(node) = resource node, :h3
      def h4(node) = resource node, :h4
      def h5(node) = resource node, :h5
      def h6(node) = resource node, :h6

      # table elements
      def table(node) = bareResource node, :table
      def thead(node) = bareResource node, :thead
      def tbody(node) = bareResource node, :tbody
      def tfoot(node) = bareResource node, :tfoot
      def th(node) = bareResource node, :th
      def tr(node) = bareResource node, :tr
      def td(node) = bareResource node, :td

      # form elements
      def form(node) = resource node, :form
      def select(node) = resource node, :select

      # text elements
      def b(node) = bareResource node, :b
      def blockquote(node) = identifiedResource node, :blockquote
      def cite(node) = identifiedResource node, :cite
      def em(node) = bareResource node, :em
      def p(node) = identifiedResource node, :p
      def strong(node) = bareResource node, :strong

      # anchor
      def a _
        _.delete Type

        if content = (_.delete Contains)
          content.map!{|c|
            HTML.markup c, env}
        end

        links = _.delete Link

        if title = (_.delete Title)
          title.map!{|c|
            HTML.markup c, env}
        end

        attrs = keyval _ unless _.empty? # remaining attributes

        links.map{|ref|
          ref = Webize::URI(ref['uri']) if ref.class == Hash
          [{_: :a, href: ref,
            class: ref.host == host ? 'local' : 'global',
            c: [title, content,
                {_: :span, class: :uri, c: CGI.escapeHTML(ref.to_s.sub /^https?:..(www.)?/, '')}]},
           attrs]} if links
      end

    end
  end
end
