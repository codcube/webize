#!/bin/sh
SRC=$HOME/src
test -d $SRC || mkdir $SRC
cd $SRC
test -d webize || git clone https://gitlab.com/ix/webize.git
cd webize && ./DEPENDENCIES.sh
