# INSTALL
``` sh
mkdir ~/src
cd ~/src
git clone git://mw.logbook.am/webize.git
cd webize && ./INSTALL # DEPENDENCIES only
```
# USAGE
``` sh
cd bin/server
./dnsd   # DNS service
./httpd  # HTTP service
```

edit behaviors in [site.rb](config/site.rb). declarative [config](config/) mostly updates at runtime. [bookmarklet](config/bookmarklet) jumps from origin to local-preference UI w/ origin cookies.
