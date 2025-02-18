# INSTALL
[a script](DEPENDENCIES.sh) calls distro packagers to install library dependencies of the Gem dependencies
then runs 'bundle install'. if that fails, see comments in the script for environment-var and other tweaks.

# CONFIG

set the cache location. this will likely move to $HOME/.cache but is currently user-defined

    export WEB=$HOME/web

you may want directories in [bin/](bin/) in **PATH**, to launch servers or do allow/block-list and subscription maintenance:

    export PATH=$HOME/src/webize/bin/config:$HOME/src/webize/bin/server:$PATH

if you use email, [procmailrc](config/dotfiles/.procmailrc) configures delivery to hour-dirs.

we type 'localhost' often without :8000 so we use the classic DNS and HTTP ports in the default config. if needed you can invent your own daemon invocations with a >1024 port specifier, or enable low-port binding on linux-compatible OS:

    sudo setcap 'cap_net_bind_service=+ep' /usr/bin/ruby

or move the priveleged-port start point:

    sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80

or change the binding port to high (>1024) and use a high-port resolver specification:

    echo nameserver 127.0.0.1 port 1053 | sudo tee /etc/resolv.conf

or redirect port 53 to a high port in kernel routing tables with the [low ports](bin/config/network/low_ports) script

or redirect traffic in userspace with netcat/socat

# USAGE

HTTP server configured for our  RDF-conversion "webizing" libraries running with [falcon](https://github.com/socketry/falcon)

    httpd

DNS server running with [async-dns](https://github.com/socketry/async-dns)

    dnsd
