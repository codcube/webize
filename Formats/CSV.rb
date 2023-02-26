# coding: utf-8
class WebResource
  module HTML

    MarkupPredicate[Schema + 'itemListElement'] = MarkupPredicate['https://schema.org/itemListElement'] = -> list, env {
      env[:sort] ||= Schema + 'position'
      list.map!{|i| i.class == Hash ? i : {'uri' => i.to_s}}
      tabular list, env}

    # tree -> table
    def self.tabular graph, env
      graph = graph.values if graph.class == Hash
      keys = graph.select{|r|r.respond_to? :keys}.map(&:keys).flatten.uniq
      env[:sort] ||= Date
      sortAttr = Webize::MetaMap[env[:sort]] || env[:sort]

      {_: :table, class: :tabular,            # table
       c: [{_: :thead,
            c: {_: :tr, c: keys.map{|p|       # table heading
                  p = p.R
                  slug = p.display_name
                  icon = Icons[p.uri] || slug
                  [{_: :th, class: p == sortAttr ? :sort : '', # ☛ sorted columns
                    c: {_: :a, href: HTTP.qs(env[:qs].merge({'sort' => p.uri, 'order' => env[:order] == 'asc' ? 'desc' : 'asc'})), c: icon}}, "\n"]}}}, "\n",
           {_: :tbody,
            c: sort(graph,env).map{|resource| # resource data
              re = if resource['uri']         # resource URI
                     resource['uri']
                   elsif resource[DC + 'identifier']
                     resource[DC + 'identifier'][0]
                   else
                     '#bnode_' + Digest::SHA2.hexdigest(rand.to_s)
                   end.to_s.R env
              types = (resource[Type]||[]).map &:to_s
              predicate = -> a {MarkupPredicate[a][resource[a],env] if resource.has_key? a}

              {_: :tr, id: re.local_id, c: keys.map{|k| # resource -> row
                 {_: :td, property: k,
                  c: if MarkupPredicate.has_key? k
                   predicate[k]
                 else
                   (resource[k]||[]).yield_self{|r|r.class == Array ? r : [r]}.map{|v|
                     [(markup v, env), ' ']}
                  end}}}}}]}
    end
  end
end
