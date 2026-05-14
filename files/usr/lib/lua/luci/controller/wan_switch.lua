module("luci.controller.wan_switch", package.seeall)

local http = require "luci.http"
local sys = require "luci.sys"

local SCRIPT = "/root/f50-wan-switch.sh"

local function trim(s)
	return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function first_line(cmd)
	return trim((sys.exec(cmd) or ""):match("([^\n]*)"))
end

local function policy_label(policy)
	if policy == "campus_first" then
		return "校园 WAN 优先"
	elseif policy == "f50_first" then
		return "F50 优先"
	end

	return policy ~= "" and policy or "未知策略"
end

local function mwan_online(status, name, fallback)
	local state = status:match("interface%s+" .. name .. "%s+is%s+(%w+)")

	if state == "online" then
		return true
	elseif state == "offline" then
		return false
	end

	return fallback
end

local function build_status()
	local out = sys.exec(SCRIPT .. " luci-status 2>/dev/null") or ""
	local mwan_status = sys.exec("mwan3 status 2>/dev/null") or ""
	local default_rule = out:match("default_rule=([^\n]+)") or ""
	local https = out:match("https=([^\n]+)") or ""
	local today, today_workday, today_source = out:match("today=([%d%-]+)%s+workday=(%w+)%s+source=(%w+)")
	local tomorrow, tomorrow_workday, tomorrow_source = out:match("tomorrow=([%d%-]+)%s+workday=(%w+)%s+source=(%w+)")
	local night_switch_hm = tonumber(out:match("night_switch_hm=(%d+)")) or 2320
	local morning_switch_hm = tonumber(out:match("morning_switch_hm=(%d+)")) or 750
	local night_switch_label = out:match("night_switch_label=([^\n]+)") or "23:20"
	local morning_switch_label = out:match("morning_switch_label=([^\n]+)") or "07:50"

	if not today then
		today, today_workday = out:match("today=([%d%-]+)%s+workday=(%w+)")
		today_source = ""
	end

	if not tomorrow then
		tomorrow, tomorrow_workday = out:match("tomorrow=([%d%-]+)%s+workday=(%w+)")
		tomorrow_source = ""
	end

	local wan_up = first_line("ifstatus wan 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null")
	local f50_up = first_line("ifstatus f50 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null")
	local wan_online = mwan_online(mwan_status, "wan", wan_up == "true")
	local f50_online = mwan_online(mwan_status, "f50", f50_up == "true")
	local wan_ip = first_line("ifstatus wan 2>/dev/null | jsonfilter -e '@[\"ipv4-address\"][0].address' 2>/dev/null")
	local f50_ip = first_line("ifstatus f50 2>/dev/null | jsonfilter -e '@[\"ipv4-address\"][0].address' 2>/dev/null")
	local hm = tonumber(os.date("%H%M")) or 0
	local outage_tonight = (tomorrow_workday == "yes")
	local morning_window = (hm < morning_switch_hm and today_workday == "yes")
	local night_window = (hm >= night_switch_hm and tomorrow_workday == "yes")
	local outage_window = morning_window or night_window
	local policy = trim(default_rule)
	local recommended_policy = outage_window and "f50_first" or "campus_first"
	local headline, level, next_action, window_label, current_exit, exit_kind, exit_ip, exit_note, protection_label

	if policy == "f50_first" then
		if f50_online then
			current_exit = "F50"
			exit_kind = "USB设备"
			exit_ip = f50_ip
			exit_note = "策略：F50 优先"
		elseif wan_online then
			current_exit = "校园 WAN"
			exit_kind = "校园网"
			exit_ip = wan_ip
			exit_note = "F50 预备中，当前由校园 WAN fallback"
		else
			current_exit = "无出口"
			exit_kind = "无可用出口"
			exit_ip = ""
			exit_note = "F50 预备中，暂无可用 fallback"
		end
	elseif policy == "campus_first" then
		if wan_online then
			current_exit = "校园 WAN"
			exit_kind = "校园网"
			exit_ip = wan_ip
			exit_note = "策略：校园 WAN 优先"
		elseif f50_online then
			current_exit = "F50"
			exit_kind = "USB设备"
			exit_ip = f50_ip
			exit_note = "校园 WAN 离线，当前由 F50 fallback"
		else
			current_exit = "无出口"
			exit_kind = "无可用出口"
			exit_ip = ""
			exit_note = "暂无可用出口"
		end
	else
		current_exit = "未知"
		exit_kind = "未知"
		exit_ip = ""
		exit_note = "未识别 mwan3 策略"
	end

	if morning_window then
		window_label = "工作日早晨断网窗口"
		next_action = morning_switch_label .. " 后自动切回校园 WAN"
	elseif night_window then
		window_label = "今晚断网窗口"
		next_action = "明早 " .. morning_switch_label .. " 后自动切回校园 WAN"
	elseif outage_tonight then
		window_label = "今晚会断网"
		next_action = night_switch_label .. " 自动切到 F50"
	else
		window_label = "今晚预计不断网"
		next_action = "保持校园 WAN"
	end

	if outage_window then
		if not f50_online then
			level = "danger"
			headline = "断网窗口：F50 离线"
		elseif policy == "f50_first" then
			level = "success"
			headline = "断网窗口：F50 保护中"
		else
			level = "danger"
			headline = "断网窗口：当前未走 F50"
		end
	elseif outage_tonight then
		if not f50_online then
			level = "danger"
			headline = "今晚会断网，但 F50 离线"
		elseif policy == "f50_first" then
			level = "success"
			headline = "今晚会断网，已提前走 F50"
		else
			level = "warning"
			headline = "今晚会断网，等待自动切换"
		end
	else
		if policy == "f50_first" then
			if f50_online then
				level = "info"
				headline = "当前走 F50，今晚预计不断网"
			elseif wan_online then
				level = "warning"
				headline = "F50 预备中，当前走校园 WAN"
			else
				level = "danger"
				headline = "F50 预备中，但暂无可用出口"
			end
		else
			if wan_online then
				level = "success"
				headline = "当前走校园 WAN，今晚预计不断网"
			elseif f50_online then
				level = "warning"
				headline = "校园 WAN 离线，当前由 F50 fallback"
			else
				level = "danger"
				headline = "暂无可用出口"
			end
		end
	end

	if outage_window then
		protection_label = (policy == "f50_first" and f50_online) and "F50 保护中" or "未保护"
	elseif policy == "f50_first" then
		protection_label = f50_online and "已提前保护" or "F50 预备中"
	else
		protection_label = "待命"
	end

	return {
		default_rule = policy,
		https = trim(https),
		today = today or "",
		today_workday = today_workday or "",
		today_source = today_source or "",
		tomorrow = tomorrow or "",
		tomorrow_workday = tomorrow_workday or "",
		tomorrow_source = tomorrow_source or "",
		wan_online = wan_online,
		f50_online = f50_online,
		wan_ip = wan_ip,
		f50_ip = f50_ip,
		now = os.date("%F %H:%M:%S"),
		current_exit = current_exit,
		policy_label = policy_label(policy),
		exit_kind = exit_kind,
		exit_ip = exit_ip,
		exit_note = exit_note,
		outage_tonight = outage_tonight,
		outage_window = outage_window,
		recommended_policy = recommended_policy,
		night_switch_label = night_switch_label,
		morning_switch_label = morning_switch_label,
		window_label = window_label,
		next_action = next_action,
		protection_label = protection_label,
		headline = headline,
		level = level
	}
end

function index()
	local page

	page = entry({"admin", "services", "wan_switch"}, form("wan_switch"), _("WAN/F50切换"), 60)
	page.dependent = true

	entry({"admin", "services", "wan_switch", "switch"}, call("action_switch")).leaf = true
	entry({"admin", "services", "wan_switch", "status"}, call("action_status")).leaf = true

	entry({"admin", "network", "wan_switch"}, alias("admin", "services", "wan_switch"), nil, 60).dependent = true
end

function action_switch()
	local target = http.formvalue("target")
	local mode

	if target == "campus" then
		mode = "campus"
	elseif target == "f50" then
		mode = "f50"
	elseif target == "auto" then
		mode = "auto"
	else
		http.status(400, "Bad Request")
		http.prepare_content("application/json")
		http.write_json({ success = false, message = "invalid target" })
		return
	end

	local rc = sys.call(SCRIPT .. " " .. mode .. " >/dev/null 2>&1")
	local status = build_status()
	local success = (rc == 0)
	local message = success and "切换完成" or "切换失败"

	if success and mode == "campus" and status.default_rule ~= "campus_first" then
		success = false
		message = "校园网未就绪，仍保持 F50"
	elseif success and mode == "f50" and status.default_rule == "f50_first" and not status.f50_online then
		message = "已预备 F50，USB 设备上线后会接管"
	elseif success and mode == "auto" then
		message = "已按自动规则切换：" .. status.policy_label
	end

	http.prepare_content("application/json")
	http.write_json({
		success = success,
		target = mode,
		message = message,
		status = status
	})
end

function action_status()
	http.prepare_content("application/json")
	http.write_json(build_status())
end
