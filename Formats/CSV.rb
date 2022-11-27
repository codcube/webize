# coding: utf-8
class WebResource

  module HTML

    MarkupPredicate[Schema + 'itemListElement'] = MarkupPredicate['https://schema.org/itemListElement'] = -> list, env {
      env[:sort] ||= Schema + 'position'
      list.map!{|i| i.class == Hash ? i : {'uri' => i.to_s}}
      tabular list, env}

    def self.group graph, env, attr=nil
      attr ||= env[:group]
      if attr                                # grouping attribute
        attr = Webize::MetaMap[attr] || attr # normalize grouping attribute
        graph.group_by{|r|                   # group resources
          (r.delete(attr) || [])[0]}
      else
        {'' => graph}                        # default group
      end
    end

    def self.sort graph, env
      attr = env[:sort] || Date                   # default to timestamp sorting
      attr = Webize::MetaMap[attr] || attr        # map sort-attribute to URI
      numeric = true if attr == Schema+'position' # numeric sort types
      sortable, unsorted = graph.partition{|r|    # to be sortable,
        r.class == Hash && (r.has_key? attr)}     # object needs sort-attribute
      sorted = sortable.sort_by{|r|               # sort the sortable objects
        numeric ? r[attr][0].yield_self{|i| i.class == Integer ? i : i.to_s.to_i} : r[attr][0].to_s}
      sorted.reverse! unless env[:order] == 'asc' # default to descending order
      [*sorted, *unsorted]                        # preserve unsorted to end of list
    end

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
