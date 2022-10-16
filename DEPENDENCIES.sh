#!/bin/sh

# Alpine https://www.alpinelinux.org/
command -v apk && sudo apk add alpine-sdk build-base linux-headers ruby ruby-dev ruby-json ruby-bigdecimal openssl-dev parallel findutils grep libxslt-dev poppler-utils ruby-bundler taglib-dev py3-pygments p11-kit-trust

# Arch https://www.archlinux.org/
command -v pacman && sudo pacman -S --needed base-devel parallel poppler ruby taglib

# Debian https://www.debian.org/
command -v apt-get && sudo apt-get install build-essential parallel ruby ruby-dev grep file libssl-dev libtag1-dev libxslt-dev libzip-dev make libffi-dev

# Gentoo https://www.gentoo.org/
command -v emerge && sudo emerge sys-process/parallel taglib

# Termux https://termux.com/
command -v pkg && pkg install binutils ruby grep gumbo-parser-static file findutils pkg-config libiconv libprotobuf libxslt parallel poppler clang taglib make libffi libcap libcrypt openssl-tool zlib

# Void https://voidlinux.org
command -v xbps-install && sudo xbps-install -S base-devel curl libltdl-devel libressl-devel parallel poppler-utils ruby ruby-devel taglib-devel

# Ruby https://www.ruby-lang.org/
command -v bundle || gem install bundler
bundle install && rm Gemfile.lock

# Nokogiri: if gems are broken on bionic/musl libc, ARM/RISC-V arch or bleeding-edge Ruby version, build locally
#  gem uninstall nokogiri -a
#  gem install --platform=ruby nokogiri -- --use-system-libraries
