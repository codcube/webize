class WebResource
  module HTML

    Markup['http://www.w3.org/ns/ldp#Container'] = -> dir, env {
      content = dir.delete('http://www.w3.org/ns/ldp#contains') || []
      [Title, Type, Date].map{|p| dir.delete p }

      uri = dir['uri'].R

      {class: :container, id: uri.fragment ? uri.fragment : '#container_' + Digest::SHA2.hexdigest(rand.to_s),
       c: [{class: :name, _: :a, href: uri.to_s,
            c: uri.fragment || uri.basename}, '<br>',
           {class: :contents,
            c: [content.map{|c| # contained items
                  c[Title] ||= [c['uri'].R.basename]
                  markup(c, env)},
                (['<hr>', keyval(dir, env)] unless dir.keys == %w(uri))]}]}} # remaining triples

    Markup['http://www.w3.org/ns/posix/stat#File'] = -> file, env {
      file.delete Type
      {class: :file,
       c: [{_: :a, href: file['uri'], class: :icon,
            c: Icons['http://www.w3.org/ns/posix/stat#File']},
           (HTML.keyval file, env)]}}

  end
end
