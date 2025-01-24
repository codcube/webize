# INSTALL
[a script](DEPENDENCIES.sh) calls distro packagers to install library dependencies of the Gem dependencies
then runs 'bundle install'. if that fails, see comments in the script for environment-var and other tweaks.

# CONFIG

set the cache location. this will likely move to $HOME/.cache but is currently user-defined

    export WEB=$HOME/web

you may want directories in [bin/](bin/) in **PATH**, to launch servers or do allow/block-list and subscription maintenance:

    export PATH=$HOME/src/webize/bin/config:$HOME/src/webize/bin/server:$PATH

if you use email, [procmailrc](config/dotfiles/.procmailrc) configures delivery to hour-dirs.

we type 'localhost' often and don't want to type :8000 so we use the classic DNS and HTTP ports of 53 and 80 in the default config. one of the tricks on [this list](https://github.com/codcube/webize/blob/main/Protocols/DNS.rb#L72) may be needed on your system, or you can simply invent your own invocations with a >1024 port specifier

in the invocations below, common HTTP_PROXY and our CDN (static-cache base URI) and OFFLINE (local-only cache) environment-vars are supported.

# USAGE

HTTP server configured for our  RDF-conversion "webizing" libraries running with [falcon](https://github.com/socketry/falcon)

    httpd

DNS server running with [async-dns](https://github.com/socketry/async-dns)

    dnsd
