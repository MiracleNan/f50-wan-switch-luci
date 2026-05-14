#!/bin/sh

set -eu

MODE="${1:-auto}"
TAG="f50-wan-switch"
CACHE_DIR="/root/.cache/f50-wan-switch"
HOLIDAY_API="https://timor.tech/api/holiday/info"
USER_AGENT="Mozilla/5.0"
CONFIG_FILE="/root/f50-wan-switch.conf"
CAMPUS_IFACE="eth1"
CAMPUS_CHECK_IP="223.5.5.5"
CAMPUS_LOGIN_URL=""
NIGHT_SWITCH_HM="2320"
MORNING_SWITCH_HM="0750"
HOLIDAY_FALLBACK_TTL="3600"

is_uint() {
	case "${1:-}" in
		""|*[!0-9]*)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

positive_int() {
	value="${1:-}"
	default="${2:-0}"

	if is_uint "$value" && [ "$value" -gt 0 ]; then
		echo "$value"
	else
		echo "$default"
	fi
}

normalize_hm() {
	value="$(printf '%s' "${1:-}" | tr -d ':[:space:]')"
	default="${2:-0}"

	if ! is_uint "$value"; then
		echo "$default"
		return 0
	fi

	value="$(printf '%s' "$value" | sed 's/^0*//')"
	[ -n "$value" ] || value=0
	echo "$value"
}

format_hm() {
	hm="$(normalize_hm "${1:-0}" 0)"
	padded="$(printf '%04d' "$hm")"
	printf '%s:%s\n' "${padded%??}" "${padded#??}"
}

if [ -r "$CONFIG_FILE" ]; then
	# shellcheck source=/dev/null
	. "$CONFIG_FILE"
fi

NIGHT_SWITCH_HM="$(normalize_hm "$NIGHT_SWITCH_HM" 2320)"
MORNING_SWITCH_HM="$(normalize_hm "$MORNING_SWITCH_HM" 750)"
HOLIDAY_FALLBACK_TTL="$(positive_int "$HOLIDAY_FALLBACK_TTL" 3600)"

date_for_offset() {
	now="$(date +%s)"
	offset="${1:-0}"
	date -d "@$((now + offset * 86400))" +%F
}

dow_for_offset() {
	now="$(date +%s)"
	offset="${1:-0}"
	date -d "@$((now + offset * 86400))" +%u
}

current_hm() {
	normalize_hm "$(date +%H%M)" 0
}

holiday_type_from_dow() {
	case "$1" in
		1|2|3|4|5)
			echo 0
			;;
		*)
			echo 1
			;;
	esac
}

holiday_info_for_date() {
	day="$1"
	dow="$2"
	cache_file="$CACHE_DIR/$day.type"
	fallback_file="$CACHE_DIR/$day.fallback"

	if [ -s "$cache_file" ]; then
		holiday_type="$(sed -n '1p' "$cache_file")"
		case "$holiday_type" in
			0|1|2|3)
				printf '%s cache\n' "$holiday_type"
				return 0
				;;
		esac
	fi

	mkdir -p "$CACHE_DIR"
	now="$(date +%s)"

	if [ -s "$fallback_file" ] && read -r saved_epoch saved_type < "$fallback_file"; then
		if is_uint "$saved_epoch" && [ $((now - saved_epoch)) -lt "$HOLIDAY_FALLBACK_TTL" ]; then
			case "$saved_type" in
				0|1|2|3)
					printf '%s fallback\n' "$saved_type"
					return 0
					;;
			esac
		fi
	fi

	if body="$(
		curl -fsS \
			-A "$USER_AGENT" \
			--connect-timeout 5 \
			--max-time 8 \
			"$HOLIDAY_API/$day" 2>/dev/null
	)"; then
		code="$(printf '%s' "$body" | jsonfilter -e '@.code' 2>/dev/null || true)"
		holiday_type="$(printf '%s' "$body" | jsonfilter -e '@.type.type' 2>/dev/null || true)"

		if [ "$code" = "0" ]; then
			case "$holiday_type" in
				0|1|2|3)
					printf '%s\n' "$holiday_type" > "$cache_file"
					rm -f "$fallback_file" 2>/dev/null || true
					printf '%s api\n' "$holiday_type"
					return 0
					;;
			esac
		fi
	fi

	holiday_type="$(holiday_type_from_dow "$dow")"
	printf '%s %s\n' "$now" "$holiday_type" > "$fallback_file"
	printf '%s fallback\n' "$holiday_type"
}

workday_info() {
	day="$1"
	dow="$2"
	info="$(holiday_info_for_date "$day" "$dow")"
	holiday_type="${info%% *}"
	source="${info#* }"

	case "$holiday_type" in
		0|3)
			printf 'yes %s\n' "$source"
			return 0
			;;
		1|2)
			printf 'no %s\n' "$source"
			return 0
			;;
	esac

	if [ "$(holiday_type_from_dow "$dow")" = "0" ]; then
		printf 'yes fallback\n'
	else
		printf 'no fallback\n'
	fi
}

is_workday() {
	day="$1"
	dow="$2"
	info="$(workday_info "$day" "$dow")"

	if [ "${info%% *}" = "yes" ]; then
		return 0
	fi

	return 1
}

choose_auto_mode() {
	hm="$(current_hm)"

	today="$(date_for_offset 0)"
	today_dow="$(dow_for_offset 0)"
	tomorrow="$(date_for_offset 1)"
	tomorrow_dow="$(dow_for_offset 1)"

	if [ "$hm" -lt "$MORNING_SWITCH_HM" ]; then
		if is_workday "$today" "$today_dow"; then
			echo f50
		else
			echo campus
		fi
	elif [ "$hm" -ge "$NIGHT_SWITCH_HM" ]; then
		if is_workday "$tomorrow" "$tomorrow_dow"; then
			echo f50
		else
			echo campus
		fi
	else
		echo campus
	fi
}

campus_online() {
	ping -I "$CAMPUS_IFACE" -c 1 -W 2 "$CAMPUS_CHECK_IP" >/dev/null 2>&1
}

login_campus() {
	[ -n "$CAMPUS_LOGIN_URL" ] || return 1

	curl -fsS \
		--interface "$CAMPUS_IFACE" \
		--connect-timeout 8 \
		--max-time 15 \
		"$CAMPUS_LOGIN_URL" >/tmp/f50-campus-login.last 2>/tmp/f50-campus-login.err
}

prepare_campus() {
	if campus_online; then
		return 0
	fi

	if login_campus; then
		sleep 2
		campus_online && return 0
	fi

	return 1
}

case "$MODE" in
	auto)
		MODE="$(choose_auto_mode)"
		;;
	day|campus|wan)
		MODE="campus"
		;;
	night|f50)
		MODE="f50"
		;;
	status|luci-status)
		today="$(date_for_offset 0)"
		today_dow="$(dow_for_offset 0)"
		tomorrow="$(date_for_offset 1)"
		tomorrow_dow="$(dow_for_offset 1)"
		today_info="$(workday_info "$today" "$today_dow")"
		tomorrow_info="$(workday_info "$tomorrow" "$tomorrow_dow")"
		echo "default_rule=$(uci -q get mwan3.default_rule.use_policy || true)"
		echo "https=$(uci -q get mwan3.https.use_policy || true)"
		echo "today=$today workday=${today_info%% *} source=${today_info#* }"
		echo "tomorrow=$tomorrow workday=${tomorrow_info%% *} source=${tomorrow_info#* }"
		echo "night_switch_hm=$NIGHT_SWITCH_HM"
		echo "morning_switch_hm=$MORNING_SWITCH_HM"
		echo "night_switch_label=$(format_hm "$NIGHT_SWITCH_HM")"
		echo "morning_switch_label=$(format_hm "$MORNING_SWITCH_HM")"
		if [ "$MODE" = "status" ]; then
			mwan3 status
		fi
		exit 0
		;;
	login|campus-login)
		if login_campus; then
			logger -t "$TAG" "campus login requested"
			exit 0
		fi
		logger -t "$TAG" "campus login failed"
		exit 1
		;;
	*)
		echo "Usage: $0 {auto|campus|f50|status|campus-login}" >&2
		exit 2
		;;
esac

case "$MODE" in
	campus)
		if ! prepare_campus; then
			logger -t "$TAG" "campus not ready, keep f50_first"
			policy="f50_first"
		else
			policy="campus_first"
		fi
		;;
	f50)
		policy="f50_first"
		;;
esac

current="$(uci -q get mwan3.default_rule.use_policy || true)"
if [ "$current" = "$policy" ]; then
	logger -t "$TAG" "policy already $policy"
	exit 0
fi

uci set mwan3.default_rule.use_policy="$policy"
if uci -q get mwan3.https >/dev/null; then
	uci set mwan3.https.use_policy="$policy"
fi
uci commit mwan3
/etc/init.d/mwan3 restart

logger -t "$TAG" "switched policy to $policy"
