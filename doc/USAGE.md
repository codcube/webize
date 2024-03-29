# USAGE
``` sh
cd bin/server
./dnsd   # DNS service
./httpd  # HTTP service
```

## environment
check out [../bin/](../bin/). we use the allow/block/follow utils for quick blocklist or subscription maintenance without opening up an editor. you might want to add some or all of these directories to **PATH** depending on what you're using, for example to enable the dnsd/httpd commands below:

    export PATH=$HOME/src/webize/bin/server:$PATH

the DNS server returns **ADDR** for names in the blocklist, to send traffic to your httpd for rewrites/substitutions. if you have a centrally-configured egress server (as expanded upon below):

    ADDR=10.10.10.1 dnsd

send all traffic to your server with **http_proxy** set at the client, or even the server in chained-proxy topologies

when **OFFLINE** is set, requests are served from local cache. for offline-mode and verbose logging launch the server with:

    CONSOLE_LEVEL=debug OFFLINE=1 httpd

set **UNFILTERED** for DNS and it will let everything through, but still highlight new domains as usual. this is one way to find new 'cookieless targeting' companies if you're looking for a job or want to add to the blocklist. set **UNFILTERED** on httpd to run an egress server:

    UNFILTERED=1 falcon -c ~/src/webize/Protocols/HTTP.ru -n 1 --bind http://10.10.10.1

## auth hoop-jumping
[bookmarklet](../config/bookmarks/UI.u) jumps context from upstream to proxy with upstream cookies. this is just enough to quell Twitter/Imperva/Incapsula errors without involving HTTPS MITM or browser plugins. Cloudflare and FB often soon revert to blocking requests. it's a huge cat&mouse game to get all potential fingerprinting sources matching a 'full fat' client with different SSL/TLS library/ciphersuites and HTTPS versions, cloned headers slightly tweaked by Rack's header-to-CGI-var munging, cache invalidations from 'Vary' headers or resource-integrity hashes, short token-expiry, HTTP-only flags on cookie visibility etc that i'm too lazy to try to make that stuff readable as it's mostly a lot of autogenerated blogspam and there's ctrl-W for when these cloud-middleware overlords are too much an adversary to basic low-traffic read-only access to the web.

## peers
each of your devices can probably (if it has 256M of RAM) host their own daemon - with the default [falcon](https://github.com/socketry/falcon) backend you no longer have to blow away scarce RAM on mobile/SBC devices with an archaic preforking model. peer servers improve cache availability during network segmentation and reduce pipe-utilization when online. define peer servers in the HOSTS file, and listen on HTTP ports on a private net provided via [Nebula](https://www.defined.net/)/[Tailscale](https://tailscale.com/)/[Zerotier](https://www.zerotier.com/), or use HTTPS on the public net. see [this](../bin/config/certificate) for certificate minting