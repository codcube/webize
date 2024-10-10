module Webize
  class HTTP::Node

    def block domain
      File.open([Webize::ConfigPath, :blocklist, :domain].join('/'), 'a'){|list|
        list << domain << "\n"} # add to blocklist
      URI.blocklist             # read blocklist
      redirect Node(['//', domain].join).href
    end

    def deny
      status = 403
      env[:deny] = true
      env[:warnings].push({_: :a,
                           id: :allow,
                           title: 'allow temporarily',
                           style: 'font-size: 3em',
                           href: Node(['//', host, path, '?allow=', allow_key].join).href,
                           c: :👁️})

      if uri.match? Gunk

        hilite = '<span style="font-size:1.2em; font-weight: bold; background-color: #f00; color: #fff">'
        unhilite = '</span>'

        if query&.match? Gunk # drop query
          env[:warnings].push ['pattern block in query:<br>',
                               {_: :a,
                                id: :noquery,
                                title: 'URI without query',
                                href: Node(['//', host, path].join).href,
                                c: [host, path], style: 'background-color: #000; color: #fff'},
                               '?',
                               query.gsub(Gunk){|m|
                                 [hilite, m, unhilite].join }]
        else
          env[:warnings].push ['pattern block in URI:<br>',
                               uri.gsub(Gunk){|m|
                                 [hilite, m, unhilite].join}]
        end

        env[:warnings].push({_: :dl, # key/val view of query args
                             c: query_values.map{|k, v|
                               vs = v.class == Array ? v : [v]
                               [{_: :dt, c: HTML.markup(k, env)},
                                vs.map{|v|
                                  {_: :dd, c: HTML.markup(v.match(/^http/) ? RDF::URI(v) : v, env)} if v
                                }]}}) if query
      end

      ext = File.extname basename if path

      type, content = if ext == '.css'
                        ['text/css', '']
                      elsif fontURI?
                        ['font/woff2', HTML::SiteFont]
                      elsif imgURI?
                        ['image/png', HTML::SiteIcon]
                      elsif ext == '.js'
                        ['application/javascript', "// URI: #{uri.match(Gunk) || host}"]
                      elsif ext == '.json'
                        ['application/json','{}']
                      else
                        ['text/html; charset=utf-8', RDF::Repository.new.dump(:html, base_uri: self)]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => origin,
        'Content-Type' => type},
       head? ? [] : [content]]
    end

  end
end
