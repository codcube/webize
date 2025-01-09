# Config/Setup
- use ~/.config/webize instead of git dir for config
- reload all conf files on ctrl-shift-R
- http, (web)socket, DNS in one process - to eliminate need for block/allowlist propagation/file-watching between processes, or for RAM efficiency on oldphone/raspi
- turtle documenting of our declarative config files - maybe w3 CSV schema since it's mostly tabular?
- systemd/openrc unit files
- gems / release version
- tests
- blocklist for message sources aka killfile

# UI
- down link on page for #fetchList populated by outbound links (load all search results)

# Model
- offline/online content merge - following feeds (API or RSS/Atom) to canonical URL may result in empty page due to SPA stuff, but we have some content already. plus the index/known-dir structures added in when live remote browsing
- define webresource level #join and call super/RDF::URI #join to eliminate manual environment threading. mild 'code could be more simple' improvements like this 
- history -  store versions
- backlink/inbound-arc + geo indexing - search for frequently linked posts 'daily heat'
- du  / triple-count on directories

# HTTP(S)
- ask all the peer-caches (pi/vps/phone from laptop) ahead of origin servers for static resources - HEAD All then cancel remaining HEADs on first response and GET winner? or announce availability at cache-time of stuff not autoimagically syndicated (larger static media stuff etc)
- auto-certgen for Falcon for full MITM for data-archival while using upstream UIs and mobile apps (See localhost gem as starting point)
- implement ruby/falcon/async/websocket streaming for earlier first byte on multi/merge-GET and update-syndication for local cluster/mesh

# Format
- path visualization (how did i get here? referer logging / backlink history)
- webize git
- timeline-histogram view


