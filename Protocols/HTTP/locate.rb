module Webize
  class HTTP::Node


    def dropQS
      if !query                         # URL is query-free
        fetch.yield_self{|s,h,b|        # call origin
          h.keys.map{|k|                # strip redirected-location query
            if k.downcase == 'location' && h[k].match?(/\?/)
              Console.logger.info "dropping query from #{h[k]}"
              h[k] = h[k].split('?')[0]
            end
          }
          [s,h,b]}                        # response
      else                                # redirect to no-query location
        Console.logger.info "dropping query from #{uri}"
        redirect Node(['//', host, path].join).href
      end
    end


    def notfound
      env[:origin_status] ||= 404
      respond [RDF::Repository.new]
    end

    def redirect(location) = [302, {'Location' => location}, []]

  end
end
