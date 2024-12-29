# Config/Setup
- use ~/.config/webize instead of git dir for config
- reload all conf files on ctrl-shift-R
- http, (web)socket, DNS in one process - to eliminate need for block/allowlist propagation/file-watching between processes, or for RAM efficiency on oldphone/raspi
- turtle documenting of our declarative config files - maybe w3 CSV schema since it's mostly tabular?
- allow comments in config formats
- systemd + openrc unit files
- gems
- tests
- blocklist for message sources (brandpoint in miltontimes/valleybreeze feeds, automod on reddit)

# UI
- down link on page for #fetchList populated by outbound links
- triple count in data-source list
- log byte-range req
- RDF(a) search hints creates toolbar searchbox. emit search hints beyond what upstreams provide in RDFa/JSON-LD
- shift-right/left pagination shortcuts conflict with text-selection adjustment - preventdefault//stop-buubbling in searchbox perhaps
- if first page is all new updates, bounded recursive fetch of next pages to catch up

# Model
- offline/online content merge - following feeds (API or RSS/Atom) to canonical URL may result in empty page due to SPA stuff, but we have some content already. plus the index/known-dir structures added in when live remote browsing
- define webresource level #join and call super/RDF::URI #join to eliminate manual environment threading.
- history -  store versions
- backlink/inbound-arc + geo indexing - search for frequently linked posts 'daily heat'
- cache redirects. instantly syndicate these (t.co dereferences, tokens and icons) to peers) 🐕➡️  http://l/2021/09/29/11/*blogpost* →  //federalhillprov.com/favicon.ico  → https://federalhillprov.com/wp-content/uploads/2021/08/cropped-fed-hill-favicon-178px-32x32.png
- du on directories
- searching a month of posts is a bit slow. collate days post's to file with one resource per line prefixed with URL for grep

# HTTP(S)
- stop redir to blocked content: http://l/2021/09/27/21/*blogpost*?view=table&sort=date →  //link.mail.bloombergbusiness.com/favicon.ico  → https://cdn.sailthru.com/assets/images/favicon.ico
- ask all the peer-caches (pi/vps/phone from laptop) ahead of origin servers for static resources - HEAD All then cancel remaining HEADs on first response and GET winner? or announce availability at cache-time of stuff not autoimagically syndicated (larger static media stuff etc)
- auto-certgen for Falcon for full MITM (See localhost gem as starting point)
- implement ioquatix 'trenni' etc streaming templates for earlier first byte on multi/merge-GET - basically required for 500-blog subscription list or we get gateway/rack/server 60s timeouts
- notification/update mesh - pick a protocol or create one (NNTP-inspired flood/gossipsub atop Solid notifications/inboxes, most likely)

# Format
- mboxes, gunzipped https://www.redhat.com/archives/dm-devel/2020-November.txt.gz
- path visualization (how did i get here? referer logging / backlink history)
- git RDFize
- view for event types https://jewishchronicle.timesofisrael.com/ - datetimeline vis
- histogram on datedir per slice-resolution
- ⚠️ no RDF reader for application/opensearchdescription+xml
- next/prev links in HTML not lifted to HTTP metadata and/or collide with proxy-added #next/#prev http://techrights.org/2021/11/30/freedom-respecting-internet/ http://www.w3.org/1999/xhtml/vocab#role

