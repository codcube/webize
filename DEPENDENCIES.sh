#!/bin/sh
# Alpine https://www.alpinelinux.org/
command -v apk && sudo apk add alpine-sdk build-base linux-headers ruby ruby-dev ruby-json ruby-bigdecimal openssl-dev parallel findutils grep libexif-dev libxslt-dev poppler-utils ruby-bundler taglib-dev py3-pygments p11-kit-trust

# Arch https://www.archlinux.org/
command -v pacman && sudo pacman -S --needed base-devel libexif parallel poppler ruby taglib

# Chromebrew https://github.com/skycocker/chromebrew
command -v crew && crew install buildessential libexif parallel taglib

# Debian https://www.debian.org/
command -v apt-get && sudo apt-get install build-essential parallel ruby ruby-dev grep file libexif-dev libssl-dev libtag1-dev libxslt-dev libzip-dev make libffi-dev

# Gentoo https://www.gentoo.org/
command -v emerge && sudo emerge libexif sys-process/parallel taglib

# Termux https://termux.com/
command -v pkg && pkg install binutils ruby grep gumbo-parser-static file findutils pkg-config libiconv libexif libprotobuf libxslt parallel poppler clang taglib make libffi libcap libcrypt openssl-tool zlib

# Void https://voidlinux.org
command -v xbps-install && sudo xbps-install -S base-devel curl libexif-devel libltdl-devel libressl-devel parallel poppler-utils ruby ruby-devel taglib-devel

# Ruby https://www.ruby-lang.org/
command -v bundle || gem install bundler
bundle install
gem install --platform=ruby nokogiri -- --use-system-libraries
