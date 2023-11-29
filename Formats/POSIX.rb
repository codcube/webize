module Webize
  module POSIX ; end

  class POSIX::Node < Resource

    def dir_triples graph
      return Node(join basename + '/').dir_triples graph unless dirURI?
      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Container))
      graph << RDF::Statement.new(self, RDF::URI(Date), node.stat.mtime.iso8601)
      children = node.children
      alpha_binning = children.size > 52
      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI(Directory)) unless alpha_binning
      graph << RDF::Statement.new(self, RDF::URI(Title), basename)
      children.select{|n|n.basename.to_s[0] != '.'}.map{|child| # 👉 contained nodes
        base = child.basename.to_s
        c = Node join base.gsub(' ','%20').gsub('#','%23')
        if child.directory?
          c += '/'
          graph << RDF::Statement.new(c, RDF::URI(Type), RDF::URI(Container))
          graph << RDF::Statement.new(c, RDF::URI(Title), base + '/')
        elsif child.file?
          graph << RDF::Statement.new(c, RDF::URI(Title), base)
          graph << RDF::Statement.new(c, RDF::URI(Type), MIME.format_icon(c.fileMIME))
        end
        if alpha_binning
          alphas = {}
          alpha = base[0].downcase
          alpha = '0' unless ('a'..'z').member? alpha
          a = RDF::URI('#' + alpha)
          alphas[alpha] ||= (
            graph << RDF::Statement.new(a, RDF::URI(Type), RDF::URI(Container))
            graph << RDF::Statement.new(a, RDF::URI(Type), RDF::URI(Directory))
            graph << RDF::Statement.new(self, RDF::URI(Contains), a))
          graph << RDF::Statement.new(a, RDF::URI(Contains), c)
        else
          graph << RDF::Statement.new(self, RDF::URI(Contains), c)
        end}
      graph
    end

    def file_triples graph
      graph << RDF::Statement.new(self, RDF::URI(Type), RDF::URI('http://www.w3.org/ns/posix/stat#File'))
      stat = File.stat fsPath
      graph << RDF::Statement.new(self, RDF::URI('http://www.w3.org/ns/posix/stat#size'), stat.size)
      graph << RDF::Statement.new(self, RDF::URI(Date), stat.mtime.iso8601)
      graph
    end

  end
  module HTML

    TabularLayout = [Directory,
                     'http://rdfs.org/sioc/ns#ChatLog']

    MarkupPredicate[Contains] = -> contents, env {
      env[:contained] ||= {} # TODO make loop-detection less crude somehow? perhaps scoped to parent containe(r) rather than entire request
      contents.map{|v|
        unless env[:contained].has_key? v['uri']
          env[:contained][v['uri']] = true
          markup v, env
        end
      }
    }

    Markup[Container] = -> dir, env {
      uri = dir['uri']
      id = RDF::URI(uri).fragment if uri
      content = dir.delete(Contains) || []
      tabular = (dir[Type] || []).find{|type| TabularLayout.member? type} && content.size > 1
      dir.delete Type
      dir.delete Date
      if title = dir.delete(Title)
        title = title[0]
        color = '#' + Digest::SHA2.hexdigest(title)[0..5]
      end
      {class: :container,
       c: [([{class: :title, c: title,
              id: 'c' + Digest::SHA2.hexdigest(rand.to_s)}.update(color ? {style: "border-color: #{color}; color: #{color}"} : {}), '<br>'] if title),
           {class: :contents, # contained nodes
            c: [if tabular
                HTML.tabular content, env
               else
                 content.map{|c|markup(c, env)}
                end,
                (['<hr>', keyval(dir, env)] unless dir.keys.empty? || dir.keys == %w(uri))]}. # key/val render of remaining triples
             update(id ? {id: id} : {}).
             update(color ? {class: 'contents columns',
                             style: "background: repeating-linear-gradient(315deg, #{color}, #{color} 1px, transparent 1px, transparent 16px); border-color: #{color}; "} : {})]}}

    Markup['http://www.w3.org/ns/posix/stat#File'] = -> file, env {
      file.delete Type
      {class: :file,
       c: [{_: :a, href: file['uri'], class: :icon,
            c: Icons['http://www.w3.org/ns/posix/stat#File']},
           (HTML.keyval file, env)]}}

  end
end
