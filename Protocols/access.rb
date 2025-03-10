module Webize
  class URI
    AllowHosts = Webize.configList 'hosts/allow'
    BlockedSchemes = Webize.configList 'blocklist/scheme'
    KillFile = Webize.configList 'blocklist/sender'
    DenyDomains = {}

    InstanceKey = Digest::SHA2.hexdigest rand.to_s

    def allow_key = Digest::SHA2.hexdigest [InstanceKey, host, path].join

    def self.blocklist
      DenyDomains.clear
      Webize.configList('blocklist/domain').map{|l|          # parse blocklist
        cursor = DenyDomains                                 # reset cursor
        l.chomp.sub(/^\./,'').split('.').reverse.map{|name|  # parse name
          cursor = cursor[name] ||= {}}}                     # initialize and advance cursor
    end
    self.blocklist                                           # load blocklist


    def deny?
      return false if temp_allow?                  # allow temporarily (keys expire on server relaunch)
      return false if AllowHosts.member? host      # allow host
      return true if BlockedSchemes.member? scheme # block scheme
      return true if uri.match? Gunk               # block URI pattern
      return false if CDN_doc?                     # allow URI pattern
      return deny_domain?                          # block domain
    end

    def deny_domain?
      return false unless host    # rule applies to domain names

      d = DenyDomains             # set cursor to base of tree

      domains.find{|name|         # parse domain name
        return unless d = d[name] # advance cursor
        d.empty? }                # named leaf exists in tree?
    end

    def temp_allow? = query_hash['allow'] == allow_key

  end
end
