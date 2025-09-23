require_relative '../index'

Async do |task|
  Webize::DNS.new.run # launch DNS server
end

run Webize::HTTP      # launch HTTP server
