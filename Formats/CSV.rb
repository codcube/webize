# coding: utf-8
class WebResource
  module HTML

    # [resource, ..] -> HTML <table>
    def self.tabular graph, env
      graph = graph.values if graph.class == Hash
      keys = graph.select{|r|r.respond_to? :keys}.map(&:keys).flatten.uniq
      {_: :table, class: :tabular,            # table
       c: [{_: :thead,
            c: {_: :tr, c: keys.map{|p|       # table heading
                  p = p.R
                  slug = p.display_name
                  icon = Icons[p.uri] || slug
                  [{_: :th,                   # ☛ sorted columns
                    c: {_: :a, c: icon,
                        href: HTTP.qs(env[:qs].merge({'sort' => p.uri,
                                                      'order' => env[:order] == 'asc' ? 'desc' : 'asc'}))}}, "\n"]}}}, "\n",
           {_: :tbody,
            c: graph.map{|resource|           # resource -> row
              predicate = -> a {MarkupPredicate[a][resource[a],env] if resource.has_key? a}

              {_: :tr, c: keys.map{|k|
                 {_: :td, property: k,
                  c: if MarkupPredicate.has_key? k
                   predicate[k]
                 else
                   (resource[k]||[]).yield_self{|r|r.class == Array ? r : [r]}.map{|v|
                     [(markup v, env), ' ']}
                  end}}}.update resource.has_key?('uri') ? {id: resource['uri'].R(env).local_id} : {}}}]} # row identifier
    end
  end
end
