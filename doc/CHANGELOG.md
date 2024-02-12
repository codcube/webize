Winter 2023

- add graph-request statistics for parse and fetch timings. enough to find what's holding up async processing. mainly a few blogs with years or decades of posts all returned at once. kind of amazing they all parsed in the 8-9s range max considering we do things like check each character for HTML escaping if it's ending up in a HTML tag, and all our machines are the lowest-end entrylevel ARM chromebooks available on refurb/closeout markets. so no reason to look into switching to Rust at this time with the great Async and RDF in Ruby. we can also cancel the TODO item to find a new base HTTP library for the fetcher now knowing what the problem was. still need to investigate how we can yield to the scheduler more often during those long-running parses in case someone wants to run a solar-powered blog archiver on a pi-zero or something.

Sep 10 01:07:53 2023 -> Mon Nov 27 09:20:35 2023 (adb0306d790901d5b38f9d6966b1de39a3c378f7 -> 6bd36a444575b927354c1cd07cd0c7aa2bd8959d)

- remove String#R shorthand to cast a URI string to a Resource. simple mechanical replace of a few hundred calls from this to RDF::URI constructors when possible, Webize::URI when additional pure URI-arithmetic functions are used, or Webize::Resource when there's an environment dependency. there's also instance-method constructors that plumb the environment through to a new object, resulting in a net reduction in verbosity when the switch from #R(env) to #URI is made to stop namespace-polluting the String class
- replace IPV4-only, bitfield-hack DNS server originally forked from a Gist with a 'real' nameserver built on Async::DNS, capable of IPV6 and better concurrency. a direct port of our old code which applies a blocklist and pretty-logs newly-encountered domains with a color scheme of orange for regex-block, red for domain-subtree block, cyan for non-www hosts - more likely to be the analytics/marketing/spyware sites we ocassionally visually scan for in the log, than the www-prefix names rendered in basic white
- add warnings about redirects when we can't return the data to the caller in HTTP metadata since it's an aggregate request. with that data we could even spit out new uri-list (.u) files with the redirections applied, but many of them are to things like domain parking/lander pages or site roots. it's still improved the situation for uri-list maintenance to only need to scan the warning-bar in the HTML rather than scroll through the server log where this data is likely flooded off by URIs of the resources found at the other URIs
- did maintenance on the URI lists for the first time in about 5 years (found some blogs that hadn't updated since 2014 that only posted for a couple months roughly when the list was born), only a few dozen to prune or fix on the Boston list. seems Blogspot-hosted domains broke HTTPS on a lot of sites but simply removing the 's' from the URL fixed these. also the usual slew of migrations to wix/squarespace/webflow which meant an elimination of the feeds we would have likely gotten had they stuck with Drupal/Wordpress and other engines born in the RSS era. we're keeping the site root in the list in the absence of feed URLs if there's regular updates, as the subpost-finding code (permalink URI search in fragment emitter) finds new posts from plain HTML that way
- with cleaned/updated lists, odd connection timeouts on large (100+ graph) lists are still an issue. it's possible there's slow processing in a triplr preventing the async scheduler from getting to other requests before timeouts we've put in. so there's still possibility we could fix this with timeouts and profiling on the triplrs rather than need to move all the fetch calls off of URI#open/Net::HTTP over to Async::HTTP. we might want to do that anyway but they're the biggest gnarliest functions in the HTTP class by far so it's hardly a priority other than this timeout issue.
- a declarative way to map URIs to new URIs is provided in the [config](https://gitlab.com/ix/webize/-/blob/main/config/hosts/forward) system. arbitrary code can also determine if a relocation should happen in the #relocate? function, and the relocation is done in #relocate. it's possible to eliminate #relocate? and just call #relocate and see if it moved, but that's a bit more expensive. we need to know if it's moved to return appropriate 301 HTTP responses. but why stop there? now pointers are updated to the new location in output RDF/HTML so clients don't have to be redirected at request time. #relocate is applied early and often, for example on the input pass of a HTML document, links to Twitter will be rewritten to Nitter, so the user never has to accidentally end up at a Twitter/X page where they're redirected to a login screen unless all their cookies are flushed and the full moon is shining. relocations are applied also for things like [URL rehosters](https://gitlab.com/ix/webize/-/blob/main/config/hosts/url?ref_type=heads) where an origin hit isn't actually required when one URI is simply encoded in the query-string of another. in some cases the relocations were completely hidden, e.g. we invisibly added .rss to Reddit URIs before origin fetches. this is now more transparent and handled via #relocate. future additions could include 'webizing' non-fetchable URLs by relocating content-address-hashes, URNs, DOIs, data-URIs, IPFS/IPLD identifiers, to gateways on the web (aka mainly localhost or peer caches/bridges).
- HTML implementation is split into 'read', 'massage', 'write' as one file was getting too unwieldy to find code we wanted. read is the HTML to RDF conversion, massage is how it's rewritten to local preferences, write is conversion of arbitrary RDF to HTML
- we loathe 'heuristics' as they lean too heavily on ad-hoc tricks, but 'subpost detection' is simply required now with so many sites having slaughtered Atom/RSS and only providing the posts inlined in a site-specific ad-hoc way to HTML or JSON. we had a subpost detector, which relied on defining CSS selectors for the posts. there's only so many popular blogging/templating engines and megasites and many users stick with the default selectors their content modules are outputting - it could easily be dialed in to correctly handle most sites we were using with only mild churn-related maintenance, but it's still too close to a heuristic based approach and required manual intervention and doesn't scale to automagically handling the output of all the long tail of static site generators (many of them never implementing feeds), i.e. the kind of content we might want to read, written by hackers and slapped up on some static host. so we got rid of that, and the 'subpost' emitter has been replaced with a 'fragment' emitter. it has a hard dependency on the 'id' attribute existing on an DOM node, so the final bridge from the old way to the new is in a few cases synthesizing identifiers as needed to bring a subpost into the world of document fragments. the emitter is implemented as a pair of recursive functions, one inside the other, with the recursion on the outer one whenever the subject URI (#fragment id) changes, and the inner one walking around DOM nodes within an identified fragment. with the document cleanly cleaved apart, output RDF is more granular, but we're still using the RDF:HTML/XMLLiteral type-tag and emitting HTML for that fragment. once upon a time this was compatible with the Tabulator and Mashlib, which's evolved into the SolidOS UI tools from Inrupt et al, but haven't checked compat lately. eliminating this and simply modeling each DOM node as an RDF node (using blank-nodes when no fragment identifier exists) is the next step and assuming there isn't much performance regression (we're already calling so many blocks/method-calls per-nokogiri-node etc, and then have this undesirably-opaque HTML blob being chucked around on top of that) we'll hopefully stop using the RDF:HTML type-tags soon

Jul 20 16:22:11 2023 -> Sep 10 01:07:53 2023 (ad57a727491c5b28f8ed5bff1bd25c71bb61214a -> adb0306d790901d5b38f9d6966b1de39a3c378f7)

- make env optional and improve text output on [tabular](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/CSV.rb#L6) renderer
- make env optional on [URI](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/HTML.rb#L560) renderer
- [declarative host categories](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/Config.rb#L37) - add forward and UI rehost categories ( extant URL rehost YT rehost categories)
- add [#relocate](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/URI.rb#L125) method
- use relocate method on [HREF](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/HTML.rb#L91) during format to prevent 301 redirects
- [declarative feed names](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/Feed.rb#L5) for when @rel isn't defined
- simplify [RSS reader](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/Feed.rb#L52)
- add [StripTags](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/HTML.rb#L19) constant, use in more places HTML input happens so \<noscript\> doesnt hide content we want to see
- add [#cachestamp](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/HTML.rb#L21) method to store base URI inline in HTML header for offline/cache resolution
- stop keyboard navigation into upstream-provided input boxes by [stripping](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/HTML.rb#L76) IDs and autofocus attrs
- generate toolbar [UI rehost](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Formats/HTML.rb#L291) links
- remove the last site-specific HTML triplr, by merging [google-searchresult](https://gitlab.com/ix/webize/-/blob/d9927c3251772ff66399fb2927bd4a7c605a5142/config/scripts/site.rb#L44) CSS hints into the subpost matcher
- remove explicit image RDF emission when also emitted in embedded HTML from HTML/feed/mardown triplrs as an alternative to runtime deduplication in the renderer. eventually we might want to turn this behaviour back on but only for summary/preview generation if we ever get around to wanting that enough (Rather than surgically requesting the exact full resources we want all the time, so like casual archive/disk browsing or index generation)
- remove [input form normalization guards](https://gitlab.com/ix/webize/-/blob/d9927c3251772ff66399fb2927bd4a7c605a5142/Formats/Image.rb#L60) for the Image and Video renderers since we're no longer running them with arbitrary unprocessed JSON now that we have better blank node support and inlining capabilities at the graph->tree conversion stage
- add activitystream parser subclassed from JSON-LD for new [nostr/fediverse-bridge](http://mw.logbook.am/image/mostr.png) use cases
- split [#fileMIME](https://gitlab.com/ix/webize/-/blob/main/Formats/MIME.rb#L20) into pure and impure versions and use the pure version when we don't need symlink following, dangling symlink existence checks and misc fs failure handling fun stuff
- remove [Link renderer](https://gitlab.com/ix/webize/-/blob/d9927c3251772ff66399fb2927bd4a7c605a5142/Formats/Message.rb#L174), use tabular renderer. made by possible by 'env is optional' changes above since we explicitly don't want request-environment hinted rewrites/relocates when outputting the original upstream links
- usual slew of [CSS tweaks](https://gitlab.com/ix/webize/-/blob/main/config/style/site.css?ref_type=heads) and rule deletions to keep up with fashions and the goal of eliminating all CSS (won't happen till we write a RDF renderer using some wayland UI toolkit. once that's done we can show the video with inlined MPV and streaming text output with $TERM and $PAGER and input boxes with $EDITOR as the creators intended and finally get rid of the chromium/firefox dependency. at no point does JAVASCRIPT enter our picture - not that we particularly dislike it but because it isn't necessary for what we're doing so we'll use stuff we like more, like Ruby+Haskell+sh. the giant $BROWSER binary is the bigger annoyance - we're still on dodgy wifi and go offline and it's as big as the rest of the OS combined in terms of download time, and if including compilation it's ~10x the time and space to build vs everything else for the OS like linux/musl/sway/foot/fuzzel/emacs, if possible. typically we cant even build it on our beefiest 4/8gb devices.. it just gets oomkilled, so any hope of building involves distcc so it fill finish in under a few days plus one device for linking with a huge swapfile on the order of most of the device size (128GB is typically our biggest storage). a binary you can't build sounds a lot like proprietary software. at least if you're sufficiently moneyed you can afford to rent a 192GB-RAM cloud build slice for your personal use so there's that. see devault's [web browsers need to stop](https://drewdevault.com/2020/08/13/Web-browsers-need-to-stop.html) and their [reckless infinite scope](https://drewdevault.com/2020/03/18/Reckless-limitless-scope). "but why would you need to build it".. if a binary existed for the obscure lowend ARM/MIPS/RISC-V stickPC/tablet on a distro using musl libc in an up to date enough version that sites arent throwing version errors, with the ungoogled/librewolf patches to remove some of the plethora of phonehome crap and defaulted-syndicated-content homepages, maybe we wouldn't need to - sometimes we've lucked out on Alpine or AUR and found what we wanted in the package manager.. but it's still no fun waiting an hour for it to DL on the coffeeshop wifi at 47.8k/s with a few timeouts/restarts when we finished drinking the coffee)
- add [#Resource](https://gitlab.com/ix/webize/-/blob/main/Formats/URI.rb?ref_type=heads#L111) and #URI methods for instantiation (aka further work on String#R removal, we're getting closer as most are now where a swap over to RDF::Vocab should work, minimal-performance-regression permitting)
- remove [#cookieCache](https://gitlab.com/ix/webize/-/blob/d9927c3251772ff66399fb2927bd4a7c605a5142/Protocols/HTTP.rb#L150). the last place we needed this was the Twitter and Gitter auth-flows, but Gitter switched to Matrix and Twitter antibotted us too much to even look into, the main site is some kind of infinite redirect loop now even in bare chromium with no extensions so IDK wtf happened there
- switch [RSS selection for reddit](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Protocols/HTTP.rb#L200) from blocklist to allowlist model as they keep adding new paths that no longer provide RSS. the main site is now often broken in this regard, and is treating name.rss as a missing resource etc. misc above changes were due to these last two issues and paving the way to enabling default/automagic forwarding to old.reddit.com and nitter and complete erasure of links to the RSS-sundowning/NonLoggedInUser-hating sites
- remove a [DNS lookup](https://gitlab.com/ix/webize/-/blob/d9927c3251772ff66399fb2927bd4a7c605a5142/Protocols/HTTP.rb#L266) incurred for local vs remote determination. still likely to get these once HTTP libraries are invoked of course, but we don't add our own
- add [timeouts](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Protocols/HTTP.rb#L255) to #fetch to try to make the 'huge feed list with now MIA or temp unavailable servers' scenario return faster. still getting weird as-yet-undiagnosed hangs deep in URI.open/Net::HTTP somewhere. quickest solution (least investigation) is switch the main fetcher over to ioquatix's async-http stuff to make this issue go away. wouldn't it be embarassing if some of thee hangs are due to our DNS server being so naiive? idk if that could be related. it's also slated for ioquatixization but as i started into that a lot of the examples seemed to not work but overall i've experienced nothing but quality from them so that's not a bad sign and who am i to talk, i dont even have unit tests, deployment automation, a written-down code of conduct or a cute logo. so we'll have to read the source, port our DNS stuff over, and see if that helps - it should with ipv6 and reverse lookups anyway, neither of which i've gotten around to implementing at all as they havent seemed super necessary so far. a 75-feed list kind of works with about 10% request failure rate given the current state of affairs but the 500-feed list for boston news is basically completely unusable as you start hitting 120s gateway/proxy/default-server-config timeouts so idk anything about the news unless it hits the scanner on 460 megacycles or staco posts about it on the elon musk site
- remove [ever expanding list of errors](https://gitlab.com/ix/webize/-/blob/d9927c3251772ff66399fb2927bd4a7c605a5142/Protocols/HTTP.rb#L417) to catch on the fetcher - catch 'em all and add a logger for HTML and console output
- add a [new path into multi-fetcher](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Protocols/HTTP.rb#L446) based on existence of local uri-list files
- simplify [#hostGET](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Protocols/HTTP.rb#L505) using changes above like the pure URI-relocation methods and elimination of no-longer-used endpoints
- [normalization](https://gitlab.com/ix/webize/-/blob/13081569080381510456d73fb4983d92b6b7a71a/Protocols/HTTP.rb#L542) of windows-1252 name variants
- usual slew of [blocklist](https://gitlab.com/ix/webize/-/tree/13081569080381510456d73fb4983d92b6b7a71a/config/blocklist) and [metadata-map](https://gitlab.com/ix/webize/-/tree/13081569080381510456d73fb4983d92b6b7a71a/config/metadata) additions and subscription-list maintenance (all but the huge one blocked on non-async-wtf issue)