#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

sh -n "$root/files/root/f50-wan-switch.sh"
sh -n "$root/files/etc/init.d/f50-wan-switch"
sh -n "$root/install-openwrt.sh"
sh -n "$root/scripts/validate.sh"

if command -v shellcheck >/dev/null 2>&1; then
	shellcheck \
		"$root/files/root/f50-wan-switch.sh" \
		"$root/files/etc/init.d/f50-wan-switch" \
		"$root/install-openwrt.sh" \
		"$root/scripts/validate.sh"
fi

if command -v luac >/dev/null 2>&1; then
	luac -p \
		"$root/files/usr/lib/lua/luci/controller/wan_switch.lua" \
		"$root/files/usr/lib/lua/luci/model/cbi/wan_switch.lua"
fi

missing_readme_paths=""
for rel in $(grep -Eo '(\.github|files|scripts|examples)/[A-Za-z0-9_./-]+|README\.md|LICENSE|CHANGELOG\.md|install-openwrt\.sh' "$root/README.md" | sort -u); do
	if [ ! -e "$root/$rel" ]; then
		missing_readme_paths="$missing_readme_paths
$rel"
	fi
done

if [ -n "$missing_readme_paths" ]; then
	printf '%s\n' "$missing_readme_paths"
	echo "README references missing path(s)." >&2
	exit 1
fi

matches=""
for file in $(find "$root" -type f \
	! -path "$root/.git/*" \
	! -path "$root/examples/f50-wan-switch.conf.example" \
	! -path "$root/scripts/validate.sh"); do
	found="$(
		grep -n -E 'user_password=|luci_password=|user_account=|CAMPUS_LOGIN_URL=.*(password|passwd|pwd)=|[0-9]{8,}@qq\.com|10\.2\.[0-9]+\.[0-9]+' "$file" \
			| grep -v 'YOUR_PASSWORD' || true
	)"

	if [ -n "$found" ]; then
		matches="$matches
$file:$found"
	fi
done

if [ -n "$matches" ]; then
	printf '%s\n' "$matches"
	echo "Potential private value found." >&2
	exit 1
fi

echo "Validation passed."
