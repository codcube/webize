class WebResource
  module HTML

    Markup['http://www.w3.org/ns/ldp#Container'] = -> dir, env {
      uri = dir['uri'].R
      tabular = dir[Type].member? 'http://www.w3.org/ns/posix/stat#Directory' # list directory in tabular layout
      content = dir.delete('http://www.w3.org/ns/ldp#contains') || []
      dir.delete Type
      dir.delete Date
      {class: :container, id: uri.fragment ? uri.fragment : '#container_' + Digest::SHA2.hexdigest(rand.to_s),
       c: [{class: :name, _: :a, href: uri.to_s,
            c: uri.fragment || uri.basename}, '<br>',
           {class: :contents, # contained nodes
            c: [if tabular
                HTML.tabular content, env
               else
                 content.map{|c|
                   c[Title] ||= [c['uri'].R.basename]
                   markup(c, env)}
                end,
                (['<hr>', keyval(dir, env)] unless dir.keys == %w(uri))]}]}} # remaining triples

    Markup['http://www.w3.org/ns/posix/stat#File'] = -> file, env {
      file.delete Type
      {class: :file,
       c: [{_: :a, href: file['uri'], class: :icon,
            c: Icons['http://www.w3.org/ns/posix/stat#File']},
           (HTML.keyval file, env)]}}

  end
end
