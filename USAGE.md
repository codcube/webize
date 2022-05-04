# USAGE
``` sh
cd bin/server
./dnsd   # DNS service
./httpd  # HTTP service
```

edit site behaviors in [site.rb](config/site.rb), though ideally none are necessar as the goal is to remove special-casing and have a fully generic proxy. declarative [config](config/) partially (blocklists do) updates at runtime, but in order to cut down on file accesses and/or shelling out (and the occasional EAGAIN errors that can occur given my incomplete understanding of Falcon and proper async code), ctrl-c or however you restart your server if heavily editing. the [bookmarklet](config/bookmarklet) jumps from origin to proxy URL with upstream cookies in tow. this is just just enough to fix Twitter/Imperva/Incapsula auth errors without involving HTTPS MITM or browser plugins, but Cloudflare is so picky that even if you allow POSTs to the origin domain for whatever challenge/response stuff, it will often soon revert to deciding you're a bot again, perhaps due to subtle changes (Rack-header header-name munging on down thru Vary headers, resource-integrity hashes etc) in the headers or short token-expiry. there's always ctrl-W when Cloudflare is too much of an adversary to basic ultra-low-traffic read-only access to the web. 