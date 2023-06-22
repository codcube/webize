class WebResource

  def dir_triples graph
    graph << RDF::Statement.new(self, Type.R, 'http://www.w3.org/ns/ldp#Container'.R)
    graph << RDF::Statement.new(self, Title.R, basename || host)
    graph << RDF::Statement.new(self, Date.R, node.stat.mtime.iso8601)
    nodes = node.children.select{|n|n.basename.to_s[0] != '.'} # find contained nodes
    nodes.map{|child|                                          # 👉 contained nodes
      graph << RDF::Statement.new(self, 'http://www.w3.org/ns/ldp#contains'.R, (join [child.basename.to_s.gsub(' ','%20').gsub('#','%23'), child.directory? ? '/' : nil].join))}
  end

  module HTML

    Markup['http://www.w3.org/ns/ldp#Container'] = -> dir, env {
      [Title, Type, Date].map{|p| dir.delete p }
      content = dir.delete('http://www.w3.org/ns/ldp#contains') || []
      {class: :container,
       c: [{class: :name,
            c: dir['uri'].R.basename, _: :a, href: dir['uri']}, '<br>',
           {class: :contents,
            c: [content.map{|c| # contained items
                  c[Title] ||= [c['uri'].R.basename]
                  markup(c, env)},
                (['<hr>', keyval(dir, env)] unless dir.keys == %w(uri))]}]}} # remaining triples

    Markup['http://www.w3.org/ns/posix/stat#File'] = -> file, env {
      [Title, Type, Date].map{|p| file.delete p }
      [({class: :file,
         c: [{_: :a, href: file['uri'], class: :icon, c: Icons['http://www.w3.org/ns/posix/stat#File']},
             {_: :span, class: :name, c: file['uri'].R.basename}]} if file['uri']),
       (HTML.keyval file, env)]}

  end
end
