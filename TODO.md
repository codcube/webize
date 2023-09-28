missing content http://localhost:8000/com/danielbachhuber/working-at-automattic/#f18efa4a785aeb87dabda0954ae72685914b72905a644498043ef39f1dc762aa8 http://l/gov/nsf/new/funding/opportunities/cyberinfrastructure-sustained-scientific
comments/posts http://localhost:8000/org/bryanalexander/technology/digg-is-going-to-kill-digg-reader-what-should-we-do-now/index.html http://l/com/reddit/old/user/squeakywipers.e84e319f01a80ba2. http://l/https://www.codeforsociety.org/news http://localhost:8000/https://www.worldwidedx.com/forums/#amateur-radio-related.64
loop http://l/pub/mostr/users/de7ecd1e2976a6adb2ffa5f4db81a7d812c8bb6698aa00dcf1e76adb55efd645/following
list render http://l/pub/mostr/users/de7ecd1e2976a6adb2ffa5f4db81a7d812c8bb6698aa00dcf1e76adb55efd645/followers
allow raw html in abstract http://l/pub/mostr/objects/5996c19eb87eb641db9826cc1c79d4cc905e7b073ffea328b6d98d34c687dca0 http://l/https://git.drupalcode.org/project/drupal/-/commits/11.x?format=atom
semiexorix image ptrs (wix JSONnonLD?) https://www.blacktimebelt.net/
css leak (multiple <body nodes) http://localhost:8000/https://theleap.org/ #ff3458a53a2c2de61a1609eec536a918c02779cbbdc45d7f6b0a1706d8b49f9b8 http://localhost:8000/fi/poutapilvi/www/index.html http://l/au/com/kidgredients/cheese-and-bacon-rolls-just-like-bakery-ones/ (we need to decide on node vs bodeset input to emitcontent) and this one is trickier, maybe coming in thru RDF::RDFa or some rouge/nokogiri cornercase w/ comments or idk PEBKAC. http://localhost:8000/https://www.cbsnews.com/news/rush-limbaugh-arrested-on-drug-charges/
subj URI collision http://localhost:8000/coop/agaric/blog/feed
new JSON Extractor . http://l/com/blastradio/ronnieloko
video tags http://localhost:8000/https://prodamdlim.akamaized.net/#p96ed80bee1d4989e50d902a0d11b0f05fc8b40868d4fedb18aefc601d52c0076
image hosts  (and the other two host types we added) http://l/2023/09/25/17/*idm.irc#prev
http://localhost:8000/https://developer.mozilla.org/en-US/blog/introducing-the-mdn-playground/

# Config/Setup
- use ~/.config/webize instead of git dir for config
- reload all the conf files on ctrl-shift-R (currently just blocklist
- turtle documenting of our declarative config files - maybe w3 CSV schema since it's mostly tabular?
- handle comments in config parsing
- systemd + openrc unit files
- gems
- tests

# UI
- down link on google for all results inlined
- JS: 'n' key jumps to first in view
- title missing if source is RDF, not HTML
- resource/update/origin-triple count in dataset list
- blank page https://efdn.notion.site/0314a1800b774258a8e6197487c479bc?v=15fb6b39a490413cbba3b7f78ad67c2b
- log byte-range req
- do any scripts still break without 'application/javascript; charset=utf-8' if h['Content-Type']=='application/javascript'?
- RDF(a) search hints creates toolbar searchbox
- shift-right/left pagination shortcuts conflict with text-selection adjustment - preventdefault//stop-buubbling in searchbox via JS , if that's where this issue was
- if first news page is all new updates, bounded recursive fetch of next pages to catch up

# Model
- populate geographic index from encountered RDF https://www.jphs.org/20th-century/2017/11/13/boston-remembers-kurt-cobain
- now that bnode/contained/referred subresource rendering is handled better, move DC:Image triples that are actually avatars to first-class avatar triple
- grep inside list http://l/src/webize/config/feeds?q=gitter
- offline/online content merge by default? following feeds (API or RSS/Atom) to canonical URL often results in empty page due to SPA stuff, but we have the content already. http://l/gitter.im/solid/specification should link to spec, solidos etc 
- define webresource level #join and call super/RDF::URI #join to eliminate manual environment threading.
- eliminate all the #R methods
- switch to RDF::Vocab instead of our hand-rolled constants, if comparable in perf
- history -  store versions/variants eg full blogpost and preview from feed may be from same "version" of resource
- backlink indexing and more indexing in general - frequently linked posts 'daily heat'
- cache redirects. instantly syndicate these (t.co dereferences, tokens and icons) to peers) 🐕➡️  http://l/2021/09/29/11/*blogpost* →  //federalhillprov.com/favicon.ico  → https://federalhillprov.com/wp-content/uploads/2021/08/cropped-fed-hill-favicon-178px-32x32.png
- du on directories

# Protocol
## misc
- finger URIs gemini://freeshell.de/gemlog/2022-01-11.gmi
- notification/update mesh - pick a protocol or create one like NNTPish atop Solid
- ipfs/ipns protocol handler https://archive.fosdem.org/2021/schedule/event/open_research_filecoin_ipfs/
- NNTP server/client
- http, (web)socket, DNS in one process (toplevel Async reactor?) for RAM efficiency on oldphone/pi3

## DNS
- replace dnsd-mini4 with rubydns/async-dns

## Gemini
- gack (gemini) server
- serve gemini from cache when gone missing gemini://rfmpie.smol.pub/reviving-macbook-with-linux

## HTTP(S)
- stop redir to blocked contetnt: http://l/2021/09/27/21/*blogpost*?view=table&sort=date →  //link.mail.bloombergbusiness.com/favicon.ico  → https://cdn.sailthru.com/assets/images/favicon.ico
- ask all the peer-caches (pi/vps/phone from laptop) ahead of origin servers for static resources - HEAD All then cancel remaining HEADs on first response and GET winner? or cache availability notices recieved via UDP mesh.  - or announce availability at cache-time of stuff not autoimagically syndicated (larger static media stuff etc)
- auto-certgen for Falcon HTTPS
- adrop specific query keys - less destructive than total qs strip - de-utmize and other gunk
- implement ioquatix streaming template stuff for earlier first byte on multi/merge-GET - basically required for 500-blog subscription list or we get gateway/rack/server 60s timeouts

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
- multiple videos, using first:https://www.youtube.com/opensearch?locale=en_US, https://www.youtube.com/watch?v=k2sIDDco5xg, http://www.youtube.com/watch?v=k2sIDDco5xg&feature=applinks, @youtube
- 12h: ⚠️ no RDF reader for application/opensearchdescription+xml
- link from parent to child resources in generic JSON triplr
- emit blank nodes in JSON triplr (requires above for reachability) https://radio.montezpress.com/api/archive/
- next/prev links in HTML not lifted to HTTP metadata and/or collide with proxy-added #next/#prev http://techrights.org/2021/11/30/freedom-respecting-internet/ http://www.w3.org/1999/xhtml/vocab#role
- link gemini posts to timeline - use current timestamp if server doesn't provide
- make HTML/RSS renderers genuine RSS:Writer instances
- ruby-net-text (gemtext) is failing on URI parse errors all the time - it shouldn't even parse the body - write a Gemini parser? do we/you use Gemini still? also TWTXT etc
- chat view
- RDF::URI #query_values hates multiple/leading/trailing &s, submit patch upstream 'https://minnit.chat/DOYOUFAMILY?embed&&nickname='.R.query_values
- re-parsing PDFs when offline http://www.midnightnotes.org/pdfnewenc9.pdf?view=table&sort=date - remove @path
- PDF images missing http://localhost:8000/https://www.bc.edu/content/dam/bc1/schools/carroll/Centers/corcoran-center/Gallivan%20Boulevard%20Concept%20Final%20-%20Spreads.pdf
- if our HTML-metadata extractor overlaps with RDFa library causing WARN predicate URI unmappped for sioc:container_of https://doriantaylor.com/summer-of-protocols/implementation-guide, remove the overlapping extracts or implement prefix expansion. a lot of non-dorian content fails to expand though anyways so we probably want a default-prefix expander no matter what

