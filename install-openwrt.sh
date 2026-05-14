#!/bin/sh

set -eu

if [ "$(id -u)" != "0" ]; then
	echo "Run this on OpenWrt as root." >&2
	exit 1
fi

if [ ! -f files/root/f50-wan-switch.sh ]; then
	echo "Run this script from the unpacked f50-wan-switch-luci-export directory." >&2
	exit 1
fi

missing=""
for cmd in mwan3 curl jsonfilter; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		missing="$missing $cmd"
	fi
done

if [ -n "$missing" ]; then
	echo "Warning: missing runtime command(s):$missing" >&2
	echo "Install them with: opkg update && opkg install mwan3 curl jsonfilter luci-app-mwan3" >&2
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup="/root/f50-wan-switch-luci-backup-$stamp.tgz"

tar czf "$backup" \
	/root/f50-wan-switch.sh \
	/usr/lib/lua/luci/controller/wan_switch.lua \
	/usr/lib/lua/luci/model/cbi/wan_switch.lua \
	/usr/lib/lua/luci/view/wan_switch/status.htm \
	/usr/share/luci/menu.d/luci-app-wan-switch.json \
	/www/luci-static/resources/view/wan_switch/status.js \
	/www/luci-static/resources/view/wan_switch/diagnostics.js \
	2>/dev/null || true

mkdir -p /root
mkdir -p /etc/init.d
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/model/cbi
mkdir -p /usr/lib/lua/luci/view/wan_switch
mkdir -p /usr/share/luci/menu.d
mkdir -p /www/luci-static/resources/view/wan_switch

cp files/root/f50-wan-switch.sh /root/f50-wan-switch.sh
cp files/etc/init.d/f50-wan-switch /etc/init.d/f50-wan-switch
cp files/usr/lib/lua/luci/controller/wan_switch.lua /usr/lib/lua/luci/controller/wan_switch.lua
cp files/usr/lib/lua/luci/model/cbi/wan_switch.lua /usr/lib/lua/luci/model/cbi/wan_switch.lua
cp files/usr/lib/lua/luci/view/wan_switch/status.htm /usr/lib/lua/luci/view/wan_switch/status.htm
cp files/usr/share/luci/menu.d/luci-app-wan-switch.json /usr/share/luci/menu.d/luci-app-wan-switch.json
cp files/www/luci-static/resources/view/wan_switch/status.js /www/luci-static/resources/view/wan_switch/status.js
cp files/www/luci-static/resources/view/wan_switch/diagnostics.js /www/luci-static/resources/view/wan_switch/diagnostics.js

chmod 755 /root/f50-wan-switch.sh
chmod 755 /etc/init.d/f50-wan-switch
chmod 644 /usr/lib/lua/luci/controller/wan_switch.lua
chmod 644 /usr/lib/lua/luci/model/cbi/wan_switch.lua
chmod 644 /usr/lib/lua/luci/view/wan_switch/status.htm
chmod 644 /usr/share/luci/menu.d/luci-app-wan-switch.json
chmod 644 /www/luci-static/resources/view/wan_switch/status.js
chmod 644 /www/luci-static/resources/view/wan_switch/diagnostics.js

rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* /tmp/luci-require-cache/* 2>/dev/null || true
/etc/init.d/uhttpd reload 2>/dev/null || true
/etc/init.d/f50-wan-switch enable 2>/dev/null || true

echo "Installed LuCI JS console, API controller, and switch script."
echo "Backup: $backup"
echo "Next: merge examples/network-f50.conf, examples/firewall-wan-zone-snippet.conf,"
echo "      examples/mwan3.conf, and examples/crontab.root into your OpenWrt config."
