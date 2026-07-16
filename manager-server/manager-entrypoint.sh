#!/bin/sh
set -eu

# palserver-gui writes the managed world settings to its read-only config
# mount. Copy them into the official image's Saved tree before every start.
mkdir -p /data/saved/Config/LinuxServer
if [ -f /data/config/PalWorldSettings.ini ]; then
    cp /data/config/PalWorldSettings.ini \
        /data/saved/Config/LinuxServer/PalWorldSettings.ini
fi

chown -R user:usergroup /data/saved

exec setpriv --reuid=user --regid=usergroup --init-groups \
    /bin/sh /pal/Package/PalServer.sh "$@"
