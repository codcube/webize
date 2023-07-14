class WebResource
  module HTML

    TabularLayout = [Directory,
                     'http://rdfs.org/sioc/ns#ChatLog']

    Markup[Container] = -> dir, env {
      uri = dir['uri'] ||= '#'
      content = dir.delete(Contains) || []
      tabular = (dir[Type] || []).find{|type| TabularLayout.member? type} && content.size > 1
      dir.delete Type
      dir.delete Date
      if title = dir.delete(Title)
        title = title[0]
        color = '#' + Digest::SHA2.hexdigest(title)[0..5]
      end
      {class: :container,
       c: [([{class: :title, _: :a, href: uri, c: title,
              id: 'c' + Digest::SHA2.hexdigest(rand.to_s)}.update(color ? {style: "border-color: #{color}; color: #{color}"} : {}), '<br>'] if title),
           {class: :contents, # contained nodes
            c: [if tabular
                HTML.tabular content, env, false
               else
                 content.map{|c|markup(c, env)}
                end,
                (['<hr>', keyval(dir, env)] unless dir.keys == %w(uri))]}. # key/val render of remaining triples
             update(color ? {style: "border-color: #{color}"} : {})]}}

    Markup['http://www.w3.org/ns/posix/stat#File'] = -> file, env {
      file.delete Type
      {class: :file,
       c: [{_: :a, href: file['uri'], class: :icon,
            c: Icons['http://www.w3.org/ns/posix/stat#File']},
           (HTML.keyval file, env)]}}

  end
end
