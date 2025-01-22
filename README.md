# INSTALL
[a script](DEPENDENCIES.sh) calls distro packagers to install library dependencies of the Gem dependencies
then runs 'bundle install'. if that fails, see comments in the script for environment-var and other tweaks.

# USAGE

set the cache location. this will likely move to $HOME/.cache but is currently user-defined

    export WEB=$HOME/web

you may want directories in [bin/](bin/) in **PATH**, to launch servers or do allow/block-list and subscription maintenance:

    export PATH=$HOME/src/webize/bin/config:$HOME/src/webize/bin/server:$PATH

if you're planning on reading mail, you may want to install the [procmailrc](config/dotfiles/.procmailrc) to deliver to hour-directories

launch:

    httpd

there's also a DNS server:

    dnsd

'webize' is a server configuration + RDF-conversion library running atop [falcon](https://github.com/socketry/falcon) and [async-dns](https://github.com/socketry/async-dns) so feel free to come up with your own invocations involving the common HTTP_PROXY and/or our CDN (shared-cache base URI) and OFFLINE (serve from cache only) environment-vars