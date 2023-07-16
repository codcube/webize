# coding: utf-8
module Webize
  module HTML

    # [resource, ..] -> HTML <table>
    def self.tabular graph, env, show_header=true
      graph = graph.values if graph.class == Hash

      keys = graph.select{|r|r.respond_to? :keys}.map(&:keys).flatten.uniq
      [Type, 'uri'].map{|k|
        if keys.member? k # move key to head of list
          keys.delete k
          keys.unshift k
        end}

      sort_attrs = [Size, Date, Title, 'uri']

      sort_attr = sort_attrs.find{|a| keys.member? a}
      sortable, rest = graph.partition{|r| # to be sortable, object needs attribute
        r.class == Hash && (r.has_key? sort_attr)}
      graph = [*sortable.sort_by{|r| r[sort_attr][0].to_s}.reverse, *rest] # sort resources

      {_: :table, class: :tabular,            # table
       c: [({_: :thead,
            c: {_: :tr, c: keys.map{|p|       # table heading
                  p = p.R
                  slug = p.display_name
                  icon = Icons[p.uri] || slug
                  [{_: :th,                   # ☛ sorted columns
                    c: {_: :a, c: icon,
                        href: URI.qs(env[:qs].merge({'sort' => p.uri,
                                                      'order' => env[:order] == 'asc' ? 'desc' : 'asc'}))}}, "\n"]}}} if show_header),
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
                  end}}}}}]} # row identifier
    end
  end
end
