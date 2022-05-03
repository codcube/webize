#!/bin/sh
SRC=$HOME/src
test -d $SRC || mkdir $SRC
cd $SRC
test -d webize || git clone git://mw.logbook.am/webize.git
cd webize && ./DEPENDENCIES.sh
