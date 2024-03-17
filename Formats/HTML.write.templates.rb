module Webize
  module HTML

    # markup-lambda tables

    # {type URI -> λ (resource, env) -> markup for resource of type }
    Markup = {}

    # {predicate URI -> λ (objects, env) -> markup for objects of predicate }
    MarkupPredicate = {}

    # templates for base types

    MarkupPredicate['uri'] = -> us, env=nil {
      (us.class == Array ? us : [us]).map{|uri|
        {_: :a, c: :🔗,
         href: env ? Webize::Resource(uri, env).href : uri,
         id: 'u' + Digest::SHA2.hexdigest(rand.to_s)}}}

    MarkupPredicate[Type] = -> types, env {
      types.map{|t|
        t = Webize::Resource t, env
        {_: :a, href: t.href,
         c: if t.uri == Contains
          nil
        elsif Icons.has_key? t.uri
          Icons[t.uri]
        else
          t.display_name
         end}}}

    MarkupPredicate[Abstract] = -> as, env {
      {class: :abstract, c: as.map{|a|[(markup a, env), ' ']}}}

    MarkupPredicate[Title] = -> ts, env {
      ts.map(&:to_s).map(&:strip).uniq.map{|t|
        [if t[0] == '#'
         {_: :span, class: :identifier, c: CGI.escapeHTML(t)}
        else
          CGI.escapeHTML t
         end, ' ']}}

    MarkupPredicate[Creator] = MarkupPredicate['http://xmlns.com/foaf/0.1/maker'] = -> creators, env {
      creators.map{|creator|
        if [Webize::URI, Webize::Resource, RDF::URI].member? creator.class
          uri = Webize::Resource.new(creator).env env
          name = uri.display_name
          color = Digest::SHA2.hexdigest(name)[0..5]
          {_: :a, class: :from, href: uri.href, style: "background-color: ##{color}", c: name}
        else
          markup creator, env
        end}}

    MarkupPredicate[To] = -> recipients, env {
      recipients.map{|r|
        if [Webize::URI, Webize::Resource, RDF::URI].member? r.class
          uri = Webize::Resource.new(r).env env
          name = uri.display_name
          color = Digest::SHA2.hexdigest(name)[0..5]
          {_: :a, class: :to, href: uri.href, style: "background-color: ##{color}", c: ['&rarr;', name].join}
        else
          markup r, env
        end}}

    Markup[Schema + 'InteractionCounter'] = -> counter, env {
      if type = counter[Schema+'interactionType']
        type = type[0].to_s
        icon = Icons[type] || type
      end
      {_: :span, class: :interactionCount,
       c: [{_: :span, class: :type, c: icon},
           {_: :span, class: :count, c: counter[Schema+'userInteractionCount']}]}}

    # MIME.format_icon(MIME.fromSuffix link.extname)
    # (MarkupPredicate[Image][n[Image],env] if n.has_key? Image),

    # eventually we'll probably merge this with BasicResource, below
    Markup[Node] = -> n, env {

      name = n[Name].first if n.has_key? Name

      # consume typetag and cleanup empty field
      n[Type] -= [RDF::URI(Node)]
      n.delete Type if n[Type].empty?

      # attrs for key/val renderer
      rest = {}
      n.map{|k,v|
        rest[k] = n[k] unless [Child, Content, Name, Sibling].member? k}

      [{_: name || :div,
        class: :node,
        c: [if n.has_key? Content
            n[Content].map{|c| markup c, env }
           else
             {_: :span, class: :name, c: name} if name
            end,

            (HTML.keyval(rest, env) unless rest.empty?),

            # child node(s)
            (n[Child].map{|child|
               Markup[Node][child, env]} if n.has_key? Child)]},

       # sibling node(s)
       (n[Sibling].map{|sibling|
          Markup[Node][sibling, env]} if n.has_key? Sibling)]}

    Markup[BasicResource] = -> re, env {
      env[:last] ||= {}                                 # previous resource

      types = (re[Type]||[]).map{|t|                    # RDF type(s)
        MetaMap[t.to_s] || t.to_s}

      classes = %w(resource)                            # CSS class(es)
      classes.push :post if types.member? Post

      p = -> a {                                        # predicate renderer
        MarkupPredicate[a][re[a],env] if re.has_key? a}

      titled = re.has_key?(Title) &&                    # has updated title?
               env[:last][Title]!=re[Title]

      if uri = re['uri']                                # unless blank node:
        uri = Webize::Resource.new(uri).env env         # full URI
        id = uri.local_id                               # fragment identifier
        origin_ref = {_: :a, class: :pointer,           # origin pointer
                      href: uri, c: :🔗}
        cache_ref = {_: :a, href: uri.href,             # cache pointer
                     id: 'p'+Digest::SHA2.hexdigest(rand.to_s)}
        color = if HostColor.has_key? uri.host          # color
                  HostColor[uri.host]
                elsif uri.deny?
                  :red
                end
      end

      from = p[Creator]                                 # sender

      if re.has_key? To                                 # receiver
        if re[To].size == 1 && [Webize::URI, Webize::Resource, RDF::URI].member?(re[To][0].class)
          color = '#' + Digest::SHA2.hexdigest(Webize::URI.new(re[To][0]).display_name)[0..5]
        end
        to = p[To]
      end

      date = p[Date]                                    # date
      link = {class: :title, c: p[Title]}.              # title
               update(cache_ref || {}) if titled
      rest = {}                                         # remaining data
      re.map{|k,v|                                      # populate remaining attrs for key/val renderer
        rest[k] = re[k] unless [Abstract, Content, Creator, Date, From, SIOC + 'richContent', Title, 'uri', To, Type].member? k}

      env[:last] = re                                   # last resource pointer TODO group by title since that's all we're deduping run-to-run?

      {class: classes.join(' '),                        # resource
       c: [link,                                        # title
           p[Abstract],                                 # abstract
           to,                                          # destination
           from,                                        # source
           date,                                        # timestamp
           [Content, SIOC+'richContent'].map{|p|
             (re[p]||[]).map{|o|markup o,env}},         # body
           (HTML.keyval(rest, env) unless rest.empty?), # key/val view of remaining data
           origin_ref,                                  # origin pointer
          ]}.update(id ? {id: id} : {}).update(color ? {style: "background: repeating-linear-gradient(45deg, #{color}, #{color} 1px, transparent 1px, transparent 8px); border-color: #{color}"} : {})}

  end
end
