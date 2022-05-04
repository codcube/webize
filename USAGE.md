# USAGE
``` sh
cd bin/server
./dnsd   # DNS service
./httpd  # HTTP service
```

## auth
[bookmarklet](config/bookmarklet) jumps from upstream to proxy URL with upstream cookies. this is just just enough to quell Twitter/Imperva/Incapsula errors without involving HTTPS MITM or browser plugins. Cloudflare and FB often soon revert to blocking requests. it's a huge cat&mouse game to get all the potential fingerprinting sources matching a 'full fat' client with different SSL/TLS library/ciphersuites and HTTPS versions and even cloned headers slightly tweaked by Rack's header-to-CGI-var case-munging, cache invalidations from 'Vary' headers or resource-integrity hashes, short token-expiry, httponly flags on cookie visibility etc that i'm too lazy to try to make that stuff readable as a lot of it is lower-tier blogspam crap and there's ctrl-W for when these cloud-middleware overlords are too much an adversary to basic low-traffic read-only access to the web.

## customization
edit site behaviors in [site.rb](config/site.rb). ideally none are necessary and the goal is to eliminate special handling. declarative [config](config/) mostly requires a process restart in order to cut down on usually-wasteful file accesses. the blocklist updates at runtime

## environment
ADDR is an address DNS server returns for names in the blocklist. another way to send traffic to the proxy is set HTTP_PROXY at the client or at the server to chain to another one. you can go without env vars or system resolver/proxy settings by using a split-horizon routing scheme for HTTP and DNS, see the commented section in [proxy_routes](bin/proxy_routes). this is the recommended approach on Android and dodgy apps that you can't trust to follow system proxy settings or not have hardcoded its own DNS servers. it requires uid separation between apps and proxy but you already have this as each app runs under its own uid. you can use this approach elsewhere - you'll need a uid for the proxy. the system may have already added one if you've installed something like squid.