# INSTALL
[a script](INSTALL.sh) uses distro pkg-managers and bundler to install gems and their dependencies. there's no gem for this library yet as there's no release version - simply require [index.rb](index.rb) and get coding, or launch one of the preconfigured servers and get webizing!

# CONFIG

set the storage base:

    export WEB=$HOME/web

you may want directories in [bin/](bin/) in **PATH**, to launch servers or do allow/block-list and subscription maintenance:

    export PATH=$HOME/src/webize/bin/config:$HOME/src/webize/bin/server:$PATH

if you use email, [procmailrc](config/dotfiles/.procmailrc) configures delivery to hour-dirs - copy it to your home dir and continue fetching/receiving mail as usual

# USAGE

HTTP server - technically a shell script with a [falcon](https://github.com/socketry/falcon) invocation

    httpd

DNS server built on [async-dns](https://github.com/socketry/async-dns) and our access rules

    dnsd
