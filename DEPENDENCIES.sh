#!/bin/sh

# Alpine https://www.alpinelinux.org/
command -v apk && sudo apk add alpine-sdk build-base linux-headers ruby ruby-dev ruby-json ruby-bigdecimal openssl-dev findutils grep libxslt-dev poppler-utils ruby-bundler taglib-dev py3-pygments p11-kit-trust yaml-dev

# Arch https://www.archlinux.org/
command -v pacman && sudo pacman -S --needed base-devel poppler ruby taglib

# Debian https://www.debian.org/
command -v apt-get && sudo apt-get install build-essential ruby ruby-dev grep file libssl-dev libtag1-dev libxslt-dev libzip-dev make libffi-dev

# Gentoo https://www.gentoo.org/
command -v emerge && sudo emerge ruby taglib

# Termux https://termux.com/
command -v pkg && pkg install binutils ruby grep gumbo-parser-static file findutils pkg-config libiconv libprotobuf libxslt poppler clang taglib make libffi libcap libcrypt openssl-tool zlib

# Void https://voidlinux.org
command -v xbps-install && sudo xbps-install -S base-devel libltdl-devel libressl-devel poppler-utils ruby ruby-devel taglib-devel

# Ruby https://www.ruby-lang.org/
command -v bundle || gem install bundler
bundle install && rm Gemfile.lock

# bundle: install may tell you it needs sudo, then if you use sudo, tell you to not install as root. so which it? we'll go with #2. put something like this in your shell .rc file:
#  export GEM_HOME="$(ruby -e 'puts Gem.user_dir')"
#  export PATH="$GEM_HOME/bin:$PATH"

# Nokogiri: if installed gem isn't working, say on bionic/musl libc (Termux/Alpine), ARM64/RISC-V architecture, or bleeding-edge git/dev-version Ruby, or especially the trifecta of these, there's some more things to try:
# build nokogiri from source:
#  gem uninstall nokogiri -a
#  gem install --platform=ruby nokogiri -- --use-system-libraries
# if this fails, try specifying the platform:
#  gem install --platform aarch64-linux-musl nokogiri
# if this throws ld errors, be sure gcompat is installed:
#  sudo apk add gcompat
# if it's still not working, maybe there's a distro supplied version:
#  sudo apk add ruby-nokogiri
# if that one's not working, maybe ask on IRC or issues tracker for help, with detailed diagnostic info from something like (if you managed to get some version installed):
#  nokogiri -v
# some info on bundler may be useful too:
#  bundle platform
#  Gemfile.lock
