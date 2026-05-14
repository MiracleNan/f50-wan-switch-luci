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

local function risk_label(level)
	if level == "success" then
		return "安全"
	elseif level == "warning" then
		return "需要关注"
	elseif level == "danger" then
		return "存在风险"
	end

	return "状态信息"
end

local function workday_label(value)
	if value == "yes" then
		return "工作日"
	elseif value == "no" then
		return "非工作日"
	end

	return "未知"
end

local function source_label(source)
	if source == "api" then
		return "节假日 API"
	elseif source == "cache" then
		return "本地缓存"
	elseif source == "fallback" then
		return "失败回退"
	elseif source == "" then
		return "未知来源"
	end

	return source
end

local function split_lines(text, limit)
	local lines = {}
	local max = limit or 40

	for line in (text or ""):gmatch("[^\n]+") do
		lines[#lines + 1] = trim(line)
		if #lines >= max then
			break
		end
	end

	return lines
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
	local recommended_action, recommended_action_label

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

	if outage_window and policy ~= "f50_first" then
		recommended_action = "f50"
		recommended_action_label = "立即启用 F50 保护"
	elseif (not outage_window) and wan_online and policy ~= "campus_first" then
		recommended_action = "campus"
		recommended_action_label = "恢复校园 WAN 优先"
	elseif recommended_policy ~= policy or current_exit == "未知" then
		recommended_action = "auto"
		recommended_action_label = "按自动规则修复"
	else
		recommended_action = "auto"
		recommended_action_label = "按自动规则检查"
	end

	local reason_lines = {}
	reason_lines[#reason_lines + 1] = "今天是" .. workday_label(today_workday or "") .. "，判断来源：" .. source_label(today_source or "") .. "。"
	reason_lines[#reason_lines + 1] = "明天是" .. workday_label(tomorrow_workday or "") .. "，判断来源：" .. source_label(tomorrow_source or "") .. "。"

	if morning_window then
		reason_lines[#reason_lines + 1] = "当前命中工作日早晨断网窗口，建议保持 F50 保护直到 " .. morning_switch_label .. " 后恢复校园 WAN。"
	elseif night_window then
		reason_lines[#reason_lines + 1] = "当前命中夜间断网窗口，建议使用 F50 保护。"
	elseif outage_tonight then
		reason_lines[#reason_lines + 1] = "今晚预计会断网，计划在 " .. night_switch_label .. " 自动切到 F50。"
	else
		reason_lines[#reason_lines + 1] = "当前不在断网窗口，默认建议校园 WAN 优先。"
	end

	if policy == recommended_policy then
		reason_lines[#reason_lines + 1] = "当前 mwan3 策略与推荐策略一致：" .. policy_label(policy) .. "。"
	else
		reason_lines[#reason_lines + 1] = "当前 mwan3 策略是 " .. policy_label(policy) .. "，推荐策略是 " .. policy_label(recommended_policy) .. "。"
	end

	if current_exit == "F50" then
		reason_lines[#reason_lines + 1] = "当前实际出口是 F50。"
	elseif current_exit == "校园 WAN" then
		reason_lines[#reason_lines + 1] = "当前实际出口是校园 WAN。"
	else
		reason_lines[#reason_lines + 1] = "当前没有确认到可用出口。"
	end

	local campus_role = "待命"
	local f50_role = "待命"

	if current_exit == "校园 WAN" then
		campus_role = "当前出口"
	elseif policy == "campus_first" then
		campus_role = "主用策略"
	end

	if current_exit == "F50" then
		f50_role = "当前出口"
	elseif policy == "f50_first" and not f50_online then
		f50_role = "预备接管"
	elseif policy == "f50_first" then
		f50_role = "主用策略"
	end

	local timeline_items = {
		{
			label = "夜间切换",
			value = night_switch_label,
			state = night_window and "active" or (outage_tonight and "pending" or "idle"),
			text = outage_tonight and ("今晚 " .. night_switch_label .. " 切到 F50") or "今晚预计不断网"
		},
		{
			label = "当前窗口",
			value = window_label,
			state = outage_window and "active" or "idle",
			text = outage_window and "正在保护窗口内" or "未进入保护窗口"
		},
		{
			label = "早晨恢复",
			value = morning_switch_label,
			state = morning_window and "active" or (outage_tonight and "pending" or "idle"),
			text = morning_switch_label .. " 后恢复校园 WAN 优先"
		}
	}

	local active_path = {
		current = current_exit,
		fallback = exit_note:match("fallback") ~= nil,
		campus = {
			online = wan_online,
			ip = wan_ip,
			role = campus_role
		},
		policy = {
			value = policy,
			label = policy_label(policy),
			recommended = recommended_policy,
			recommended_label = policy_label(recommended_policy),
			matches_recommendation = policy == recommended_policy
		},
		f50 = {
			online = f50_online,
			ip = f50_ip,
			role = f50_role
		}
	}

	local diagnostics_summary = "mwan3=" .. (policy ~= "" and policy or "unknown")
		.. "，WAN=" .. (wan_online and "online" or "offline")
		.. "，F50=" .. (f50_online and "online" or "offline")
		.. "，工作日来源=" .. source_label(tomorrow_source or today_source or "")

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
		level = level,
		last_refresh_epoch = os.time(),
		risk_level = level,
		risk_label = risk_label(level),
		recommended_action = recommended_action,
		recommended_action_label = recommended_action_label,
		reason_lines = reason_lines,
		timeline_items = timeline_items,
		active_path = active_path,
		diagnostics_summary = diagnostics_summary
	}
end

local function iface_summary(name)
	local up = first_line("ifstatus " .. name .. " 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null")

	return {
		name = name,
		up = up == "true",
		proto = first_line("ifstatus " .. name .. " 2>/dev/null | jsonfilter -e '@.proto' 2>/dev/null"),
		device = first_line("ifstatus " .. name .. " 2>/dev/null | jsonfilter -e '@.device' 2>/dev/null"),
		l3_device = first_line("ifstatus " .. name .. " 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null"),
		ip = first_line("ifstatus " .. name .. " 2>/dev/null | jsonfilter -e '@[\"ipv4-address\"][0].address' 2>/dev/null"),
		gateway = first_line("ifstatus " .. name .. " 2>/dev/null | jsonfilter -e '@.route[0].nexthop' 2>/dev/null")
	}
end

local function cache_status()
	local dir = "/root/.cache/f50-wan-switch"
	local exists = first_line("[ -d " .. dir .. " ] && echo yes || echo no") == "yes"

	return {
		directory = dir,
		exists = exists,
		files = split_lines(sys.exec("ls -1 " .. dir .. " 2>/dev/null | sed -n '1,20p'") or "", 20)
	}
end

local function portal_status()
	local config_present = first_line("[ -r /root/f50-wan-switch.conf ] && echo yes || echo no") == "yes"
	local login_configured = first_line("sh -c '. /root/f50-wan-switch.conf 2>/dev/null; [ -n \"$CAMPUS_LOGIN_URL\" ] && echo yes || echo no'") == "yes"

	return {
		config_present = config_present,
		login_configured = login_configured,
		note = login_configured and "已配置校园网认证命令" or "未配置校园网认证命令"
	}
end

local function build_diagnostics_status()
	local status = build_status()
	local mwan_status = sys.exec("mwan3 status 2>/dev/null") or ""
	local script_status = sys.exec(SCRIPT .. " luci-status 2>/dev/null") or ""
	local recent_logs = split_lines(sys.exec("logread 2>/dev/null | grep 'f50-wan-switch' | tail -20") or "", 20)

	return {
		generated_at = os.date("%F %H:%M:%S"),
		status = status,
		mwan3_summary = split_lines(mwan_status, 80),
		ifstatus = {
			wan = iface_summary("wan"),
			f50 = iface_summary("f50")
		},
		workday = {
			today = status.today,
			today_workday = status.today_workday,
			today_source = status.today_source,
			tomorrow = status.tomorrow,
			tomorrow_workday = status.tomorrow_workday,
			tomorrow_source = status.tomorrow_source
		},
		cache = cache_status(),
		recent_logs = recent_logs,
		last_switch_result = recent_logs[#recent_logs] or "",
		script_status = split_lines(script_status, 40),
		portal = portal_status()
	}
end

function index()
	entry({"admin", "services", "wan_switch", "switch"}, call("action_switch")).leaf = true
	entry({"admin", "services", "wan_switch", "status"}, call("action_status")).leaf = true
	entry({"admin", "services", "wan_switch", "diagnostics_status"}, call("action_diagnostics_status")).leaf = true

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

function action_diagnostics_status()
	http.prepare_content("application/json")
	http.write_json(build_diagnostics_status())
end
