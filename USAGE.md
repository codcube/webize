# USAGE
``` sh
cd bin/server
./dnsd   # DNS service
./httpd  # HTTP service
```

edit site behaviors in [site.rb](config/site.rb), though ideally none are necessary as the goal is to remove special handling for a fully generic proxy. declarative [config](config/) partially (blocklists) update at runtime, but in order to cut down on file accesses and/or shelling out (and the occasional EAGAIN errors that can occur given my incomplete understanding of Falcon and proper async code), ctrl-c or however you restart your server if heavily editing. the [bookmarklet](config/bookmarklet) jumps from origin to proxy URL with upstream cookies in tow. this is just just enough to fix Twitter/Imperva/Incapsula auth errors without involving HTTPS MITM or browser plugins, but Cloudflare is picky so even if you've allowed POSTs to the origin domain for a challenge/response, it will often soon revert to deciding you're a bot, due to subtle changes (Rack-header-to-CGI-var case-munging, invalidations via the 'Vary' headers or resource-integrity hashes, short token-expiry, httponly flags on cookie visibility etc) that i'm too lazy to look into as there's currently ctrl-W for when Cloudflare is too much of an adversary to basic ultra-low-traffic read-only access to the web. 