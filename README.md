# webize

# INSTALL
[a script](DEPENDENCIES.sh) calls distro packagers to install build-time dependencies for the Gem dependencies,
the runs 'bundle install'. if that fails, see comments in the script for environment-var and other tweaks.

# USAGE

set the cache location. this will likely move to $HOME/.cache but is currently user-defined

    export WEB=$HOME/web

you may want directories in [bin/](bin/) in **PATH**, to launch servers or do allow/block-list and subscription maintenance:

    export PATH=$HOME/src/webize/bin/config:$HOME/src/webize/bin/server:$PATH

launch:

    httpd

when **OFFLINE** is set, requests are served from local cache. for an offline, verbose server:

    CONSOLE_LEVEL=debug OFFLINE=1 httpd

there's also an optional DNS server

    dnsd

everything is really a configuration + app atop falcon and async-dns so feel free to come up with your own ideas