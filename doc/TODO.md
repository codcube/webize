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
- blank page https://efdn.notion.site/0314a1800b774258a8e6197487c479bc?v=15fb6b39a490413cbba3b7f78ad67c2b
- log byte-range req
- do any scripts still break without 'application/javascript; charset=utf-8' if h['Content-Type']=='application/javascript'?
- RDF(a) search hints creates toolbar searchbox
- shift-right/left pagination shortcuts conflict with text-selection adjustment - preventdefault//stop-buubbling in searchbox via JS , if that's where this issue was
- if first news page is all new updates, bounded recursive fetch of next pages to catch up

# Model
- remove requirement for explicit graph specification in triplrs, it's implicit in the request and resource URIs. we can now use #relocate to move resources to better URIs if absolutely necessary.  in aggregation scenarios (feed/update endpoints), the graph URI is currently being set to the canonical location of the individual resource so it's stored there rather than under the feed URL. we'll probably change the graph URI to just be the URI the resources were found at, and add better provenance linking back to that when linking the canonical location. 
- populate geographic index from encountered RDF https://www.jphs.org/20th-century/2017/11/13/boston-remembers-kurt-cobain
- now that bnode/contained/referred subresource rendering is handled better, move DC:Image triples that are actually avatars to first-class avatar triple
- grep inside list http://l/src/webize/config/feeds?q=gitter
- offline/online content merge by default? following feeds (API or RSS/Atom) to canonical URL often results in empty page due to SPA stuff, but we have the content already. http://l/gitter.im/solid/specification should link to spec, solidos etc 
- define webresource level #join and call super/RDF::URI #join to eliminate manual environment threading.
- history -  store versions/variants eg full blogpost and preview from feed may be from same "version" of resource
- backlink indexing and more indexing in general - frequently linked posts 'daily heat'
- cache redirects. instantly syndicate these (t.co dereferences, tokens and icons) to peers) 🐕➡️  http://l/2021/09/29/11/*blogpost* →  //federalhillprov.com/favicon.ico  → https://federalhillprov.com/wp-content/uploads/2021/08/cropped-fed-hill-favicon-178px-32x32.png
- du on directories
- searching a month of posts is a bit slow. usualy like 20-30 seconds (including system grep calls plus parse/load/render time of results through the stack) for 50,000 files on cheapest netbook with minimal storage. collating each days posts into a file (previous daydirs stop updating right away) with one post per line and emitting the relative URL from grep etc should fix this
- http://l/2023/12/02/?q=hyde%20park has results but http://l/2023/12/02/?q=%22hyde%20park%22 doesn't even though the output text matches. related to above do we need a plaintext version so %20 etc aren't fooling grep.. probably

# HTTP(S)
- stop redir to blocked content: http://l/2021/09/27/21/*blogpost*?view=table&sort=date →  //link.mail.bloombergbusiness.com/favicon.ico  → https://cdn.sailthru.com/assets/images/favicon.ico
- ask all the peer-caches (pi/vps/phone from laptop) ahead of origin servers for static resources - HEAD All then cancel remaining HEADs on first response and GET winner? or announce availability at cache-time of stuff not autoimagically syndicated (larger static media stuff etc)
- auto-certgen for Falcon for full MITM (See localhost gem as starting point)
- drop specific query keys - less destructive than total qs strip - de-utmize and other gunk
- implement ioquatix 'trenni' etc streaming templates for earlier first byte on multi/merge-GET - basically required for 500-blog subscription list or we get gateway/rack/server 60s timeouts
- notification/update mesh - pick a protocol or create one (NNTP-inspired flood/gossipsub atop Solid notifications/inboxes, most likely)
- use rdf schema in http metadata cache

# Format
- mboxes, gunzipped https://www.redhat.com/archives/dm-devel/2020-November.txt.gz
- path visualization (how did i get here? referer logging / backlink history)
- git RDFize
- view for event types https://jewishchronicle.timesofisrael.com/ - datetimeline vis
- RDFa output - investigate HAML template-solution in RDF library or just add it to native views. not many to edit
- histogram on datedir per slice-resolution
- hash fetched entities to prevent redundant parsing/summarization work when origin caching is broken - essentially generate our own ETags
- for pages still completely blank - https://laiyiohlsen.com/projects/while-x.html - multifetch triplr on the Link field (the text is inside included JS files in this case)
- dedupe images, link to shown image from placeholder icons
- assemble dash/hls manifest for youtube data we have from the json , so we can stop using their borked player with the unskippable adloop bug
- ⚠️ no RDF reader for application/opensearchdescription+xml
- redo JSON triplr too topofdoc https://radio.montezpress.com/api/archive/
- next/prev links in HTML not lifted to HTTP metadata and/or collide with proxy-added #next/#prev http://techrights.org/2021/11/30/freedom-respecting-internet/ http://www.w3.org/1999/xhtml/vocab#role
- link gemini posts to timeline - use current timestamp if server doesn't provide
- ruby-net-text (gemtext) is failing on URI parse errors all the time - it shouldn't even parse the body - write a Gemini parser? do we/you use Gemini still? also TWTXT etc
- chat view
- re-parsing PDFs when offline http://www.midnightnotes.org/pdfnewenc9.pdf?view=table&sort=date (remove @path), images missing http://localhost:8000/https://www.bc.edu/content/dam/bc1/schools/carroll/Centers/corcoran-center/Gallivan%20Boulevard%20Concept%20Final%20-%20Spreads.pdf
