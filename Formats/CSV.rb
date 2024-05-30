# coding: utf-8
module Webize
  module HTML

    # [resource, ..] -> HTML <table>
    def self.tabular graph, env = nil
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
                  p = Webize::URI(p)
                  slug = p.display_name
                  icon = Icons[p.uri] || slug
                  [{_: :th,                   # ☛ sorted columns
                    c: {_: :a, c: icon,
                        href: URI.qs(env[:qs].merge({'sort' => p.uri,
                                                      'order' => env[:order] == 'asc' ? 'desc' : 'asc'}))}}, "\n"]}}} if env),
           {_: :tbody,
            c: graph.map{|resource|           # resource -> row
              [{_: :tr, c: keys.map{|k|
                  [{_: :td, property: k,
                    c: property(k, resource[k]), "\n" ]}}, "\n" ]}}]}
    end
  end
end
