# Config/Setup
- use ~/.config/webize instead of git dir for config
- reload all conf files on ctrl-shift-R
- http, (web)socket, DNS in one process - toplevel Async reactor for RAM efficiency on oldphone/pi<4
- turtle documenting of our declarative config files - maybe w3 CSV schema since it's mostly tabular?
- handle comments in config parsing
- systemd + openrc unit files
- gems
- tests
- killfile for users (brandpoint in miltontimes/valleybreeze feeds, automod on reddit)

# UI
- down link on google for all results inlined
- title missing if source is RDF, not HTML
- resource/update/origin-triple count in dataset list
- log byte-range req
- RDF(a) search hints creates toolbar searchbox
- shift-right/left pagination shortcuts conflict with text-selection adjustment - preventdefault//stop-buubbling in searchbox via JS , if that's where this issue was
- if first news page is all new updates, bounded recursive fetch of next pages to catch up

# Model
- populate geographic index from encountered RDF https://www.jphs.org/20th-century/2017/11/13/boston-remembers-kurt-cobain
- offline/online content merge by default? following feeds (API or RSS/Atom) to canonical URL often results in empty page due to SPA stuff, but we have the content already. http://l/gitter.im/solid/specification should link to spec, solidos etc 
- define webresource level #join and call super/RDF::URI #join to eliminate manual environment threading.
- history -  store versions/variants eg full blogpost and preview from feed may be from same "version" of resource
- backlink indexing and more indexing in general - frequently linked posts 'daily heat'
- cache redirects. instantly syndicate these (t.co dereferences, tokens and icons) to peers) 🐕➡️  http://l/2021/09/29/11/*blogpost* →  //federalhillprov.com/favicon.ico  → https://federalhillprov.com/wp-content/uploads/2021/08/cropped-fed-hill-favicon-178px-32x32.png
- du on directories
- searching a month of posts is a bit slow. usualy like 20-30 seconds (including system grep calls plus parse/load/render time of results through the stack) for 50,000 files on cheapest netbook with minimal storage. collating each days posts into a file (previous daydirs stop updating right away) with one post per line and emitting the relative URL from grep etc should fix this

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
- hash fetched entities to prevent redundant parsing/summarization work when origin caching is broken - essentially generate our own ETags
- assemble dash/hls manifest for youtube data we have from the json , so we can stop using their borked player with the unskippable adloop bug
- ⚠️ no RDF reader for application/opensearchdescription+xml
- next/prev links in HTML not lifted to HTTP metadata and/or collide with proxy-added #next/#prev http://techrights.org/2021/11/30/freedom-respecting-internet/ http://www.w3.org/1999/xhtml/vocab#role

