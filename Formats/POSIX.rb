class WebResource
  module HTML

    TabularLayout = [Directory,
                     'http://rdfs.org/sioc/ns#ChatLog']

    Markup[Container] = -> dir, env {
      uri = dir['uri'].R
      content = dir.delete(Contains) || []
      tabular = (dir[Type] || []).find{|type| TabularLayout.member? type} && content.size > 1
      dir.delete Type
      dir.delete Date
      title = dir.has_key?(Title) ? dir.delete(Title)[0] : uri.display_name
      {class: :container,
       c: [{class: :title, _: :a, href: uri.to_s, c: title, id: 'c' + Digest::SHA2.hexdigest(rand.to_s)}, '<br>',
           {class: :contents, # contained nodes
            c: [if tabular
                HTML.tabular content, env, false
               else
                 content.map{|c|markup(c, env)}
                end,
                (['<hr>', keyval(dir, env)] unless dir.keys == %w(uri))]}]}} # key/val render of remaining triples

    Markup['http://www.w3.org/ns/posix/stat#File'] = -> file, env {
      file.delete Type
      {class: :file,
       c: [{_: :a, href: file['uri'], class: :icon,
            c: Icons['http://www.w3.org/ns/posix/stat#File']},
           (HTML.keyval file, env)]}}

  end
end
