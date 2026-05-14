'use strict';
'require view';
'require request';
'require poll';
'require ui';

var stateHost = null;
var messageHost = null;
var currentStatus = null;
var busyTarget = null;
var pollStarted = false;

var STYLE = [
	':root { --ws-bg: #f6f8fb; --ws-surface: #ffffff; --ws-text: #172033; --ws-muted: #5f6c82; --ws-line: #dce4ef; --ws-soft: #f1f5f9; --ws-success: #137a5b; --ws-success-bg: #e9f7f1; --ws-warning: #9a5b00; --ws-warning-bg: #fff7e6; --ws-danger: #ba332b; --ws-danger-bg: #fff0ee; --ws-info: #245d9f; --ws-info-bg: #eaf3fb; --ws-shadow: 0 10px 28px rgba(18, 32, 52, .07); }',
	'.wan-switch-console { color: var(--ws-text); max-width: 1160px; margin: 0 auto; overflow-x: hidden; padding-bottom: 92px; }',
	'.wan-switch-console * { box-sizing: border-box; min-width: 0; }',
	'.wan-switch-title { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; flex-wrap: wrap; margin: 0 0 16px; }',
	'.wan-switch-title h2 { margin: 0; font-size: 24px; line-height: 1.25; font-weight: 700; }',
	'.wan-switch-title p { margin: 6px 0 0; color: var(--ws-muted); }',
	'.ws-toolbar { display: flex; gap: 8px; flex-wrap: wrap; }',
	'.ws-message { border-radius: 10px; padding: 10px 12px; margin-bottom: 12px; border: 1px solid var(--ws-line); background: var(--ws-soft); color: var(--ws-text); }',
	'.ws-message.is-hidden { display: none; }',
	'.ws-message.ws-level-success { background: var(--ws-success-bg); color: var(--ws-success); border-color: rgba(19, 122, 91, .26); }',
	'.ws-message.ws-level-warning { background: var(--ws-warning-bg); color: var(--ws-warning); border-color: rgba(154, 91, 0, .26); }',
	'.ws-message.ws-level-danger { background: var(--ws-danger-bg); color: var(--ws-danger); border-color: rgba(186, 51, 43, .26); }',
	'.ws-message.ws-level-info { background: var(--ws-info-bg); color: var(--ws-info); border-color: rgba(36, 93, 159, .22); }',
	'.ws-grid { display: grid; grid-template-columns: minmax(0, 1fr); gap: 14px; }',
	'.ws-overview { display: grid; grid-template-columns: minmax(0, 1.55fr) minmax(300px, .75fr); gap: 14px; align-items: stretch; }',
	'.ws-secondary-grid { display: grid; grid-template-columns: minmax(0, 1.2fr) minmax(320px, .8fr); gap: 14px; align-items: start; }',
	'.ws-hero { position: relative; border-radius: 12px; padding: 18px; background: var(--ws-surface); border: 1px solid var(--ws-line); box-shadow: var(--ws-shadow); overflow: hidden; }',
	'.ws-hero:before { content: ""; position: absolute; inset: 0 0 auto; height: 4px; background: var(--ws-info); }',
	'.ws-hero.ws-level-success { background: linear-gradient(180deg, #f7fffb 0%, #fff 72%); border-color: rgba(19, 122, 91, .22); }',
	'.ws-hero.ws-level-warning { background: linear-gradient(180deg, #fffaf0 0%, #fff 72%); border-color: rgba(154, 91, 0, .22); }',
	'.ws-hero.ws-level-danger { background: linear-gradient(180deg, #fff5f3 0%, #fff 72%); border-color: rgba(186, 51, 43, .24); }',
	'.ws-hero.ws-level-info { background: linear-gradient(180deg, #f3f8fe 0%, #fff 72%); border-color: rgba(36, 93, 159, .22); }',
	'.ws-hero.ws-level-success:before { background: var(--ws-success); }',
	'.ws-hero.ws-level-warning:before { background: var(--ws-warning); }',
	'.ws-hero.ws-level-danger:before { background: var(--ws-danger); }',
	'.ws-hero.ws-level-info:before { background: var(--ws-info); }',
	'.ws-hero-inner { display: grid; gap: 14px; }',
	'.ws-hero h1 { margin: 8px 0 8px; font-size: 32px; line-height: 1.15; letter-spacing: 0; }',
	'.ws-hero-summary { color: var(--ws-muted); font-size: 14px; line-height: 1.55; }',
	'.ws-status-facts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; margin-top: 4px; }',
	'.ws-fact { border: 1px solid var(--ws-line); border-radius: 10px; background: rgba(255, 255, 255, .72); padding: 10px; }',
	'.ws-fact-label { color: var(--ws-muted); font-size: 12px; margin-bottom: 4px; }',
	'.ws-fact-value { font-size: 16px; font-weight: 700; line-height: 1.25; overflow-wrap: anywhere; }',
	'.ws-fact-note { color: var(--ws-muted); font-size: 12px; margin-top: 4px; line-height: 1.35; overflow-wrap: anywhere; }',
	'.ws-refresh-line { color: var(--ws-muted); font-size: 12px; margin-top: 4px; }',
	'.ws-card { background: var(--ws-surface); border: 1px solid var(--ws-line); border-radius: 12px; padding: 14px; box-shadow: 0 6px 18px rgba(18, 32, 52, .04); }',
	'.ws-card h3 { margin: 0 0 12px; font-size: 16px; line-height: 1.35; }',
	'.ws-card-subtle { color: var(--ws-muted); margin: -6px 0 12px; line-height: 1.5; }',
	'.ws-pill { display: inline-flex; align-items: center; justify-content: center; gap: 6px; width: fit-content; max-width: 100%; flex: 0 0 auto; align-self: flex-start; border-radius: 999px; padding: 4px 9px; font-size: 12px; line-height: 1.2; font-weight: 650; white-space: normal; }',
	'.ws-node-head .ws-pill { align-self: center; }',
	'.ws-pill.ws-level-success { color: var(--ws-success); background: var(--ws-success-bg); }',
	'.ws-pill.ws-level-warning { color: var(--ws-warning); background: var(--ws-warning-bg); }',
	'.ws-pill.ws-level-danger { color: var(--ws-danger); background: var(--ws-danger-bg); }',
	'.ws-pill.ws-level-info { color: var(--ws-info); background: var(--ws-info-bg); }',
	'.ws-pill.ws-level-neutral { color: var(--ws-muted); background: var(--ws-soft); }',
	'.ws-path { display: grid; grid-template-columns: minmax(0, 1fr) auto minmax(0, .75fr) auto minmax(0, 1fr); gap: 10px; align-items: stretch; }',
	'.ws-path-node { border: 1px solid var(--ws-line); border-radius: 12px; padding: 12px; background: #fbfdff; display: grid; gap: 8px; }',
	'.ws-path-node.is-current { border-color: rgba(22, 132, 91, .45); background: var(--ws-success-bg); }',
	'.ws-path-node.is-prepared { border-color: rgba(37, 99, 168, .32); background: var(--ws-info-bg); }',
	'.ws-node-head { display: flex; justify-content: space-between; gap: 8px; align-items: center; flex-wrap: wrap; }',
	'.ws-node-name { font-size: 16px; font-weight: 700; }',
	'.ws-node-ip { color: var(--ws-muted); font-size: 13px; overflow-wrap: anywhere; }',
	'.ws-path-arrow { display: flex; align-items: center; justify-content: center; color: var(--ws-muted); font-weight: 700; }',
	'.ws-policy-node { text-align: center; justify-content: center; background: var(--ws-soft); }',
	'.ws-policy-node strong { display: block; margin-bottom: 4px; }',
	'.ws-timeline { display: grid; grid-template-columns: minmax(0, 1fr); gap: 10px; }',
	'.ws-step { border: 1px solid var(--ws-line); border-radius: 12px; padding: 12px; background: #fbfdff; }',
	'.ws-step.ws-step-active { border-color: rgba(36, 93, 159, .35); background: var(--ws-info-bg); }',
	'.ws-step.ws-step-pending { border-color: rgba(154, 91, 0, .25); background: var(--ws-warning-bg); }',
	'.ws-step-label { color: var(--ws-muted); font-size: 12px; margin-bottom: 5px; }',
	'.ws-step-value { font-weight: 700; font-size: 16px; line-height: 1.3; overflow-wrap: anywhere; }',
	'.ws-step-text { color: var(--ws-muted); font-size: 12px; margin-top: 5px; line-height: 1.35; }',
	'.ws-action-layout { display: grid; gap: 12px; align-items: stretch; }',
	'.ws-primary-action { display: grid; gap: 10px; align-content: start; }',
	'.ws-action-title { font-size: 18px; font-weight: 700; }',
	'.ws-action-note { color: var(--ws-muted); line-height: 1.5; }',
	'.ws-button-row { display: flex; flex-wrap: wrap; gap: 8px; }',
	'.ws-btn { appearance: none; border: 1px solid var(--ws-line); border-radius: 10px; background: var(--ws-surface); color: var(--ws-text); padding: 9px 12px; font-weight: 650; line-height: 1.2; cursor: pointer; transition: background .15s ease, border-color .15s ease, transform .15s ease, opacity .15s ease; white-space: normal; text-align: center; }',
	'.ws-btn:hover:not(:disabled) { background: var(--ws-soft); border-color: #c7d1df; }',
	'.ws-btn:active:not(:disabled) { transform: translateY(1px); }',
	'.ws-btn:disabled { opacity: .55; cursor: wait; }',
	'.ws-btn.ws-primary { background: var(--ws-info); border-color: var(--ws-info); color: #fff; }',
	'.ws-btn.ws-primary.ws-level-success { background: var(--ws-success); border-color: var(--ws-success); }',
	'.ws-btn.ws-primary.ws-level-warning { background: var(--ws-warning); border-color: var(--ws-warning); }',
	'.ws-btn.ws-primary.ws-level-danger { background: var(--ws-danger); border-color: var(--ws-danger); }',
	'.ws-btn.ws-primary.ws-level-info { background: var(--ws-info); border-color: var(--ws-info); }',
	'.ws-btn.weak { border-style: dashed; color: var(--ws-muted); }',
	'.ws-more { background: var(--ws-surface); border: 1px solid var(--ws-line); border-radius: 12px; padding: 0; box-shadow: 0 6px 18px rgba(18, 32, 52, .04); overflow: hidden; }',
	'.ws-more summary { cursor: pointer; list-style: none; padding: 14px; font-weight: 700; display: flex; align-items: center; justify-content: space-between; gap: 12px; }',
	'.ws-more summary::-webkit-details-marker { display: none; }',
	'.ws-more summary:after { content: "展开"; color: var(--ws-muted); font-size: 12px; font-weight: 650; }',
	'.ws-more[open] summary:after { content: "收起"; }',
	'.ws-more-body { border-top: 1px solid var(--ws-line); padding: 14px; display: grid; grid-template-columns: minmax(0, .9fr) minmax(0, 1.1fr); gap: 16px; }',
	'.ws-more-panel h3 { margin: 0 0 10px; font-size: 15px; }',
	'.ws-detail-rows { display: grid; gap: 8px; }',
	'.ws-detail-row { display: grid; grid-template-columns: 110px minmax(0, 1fr); gap: 10px; align-items: start; padding-bottom: 8px; border-bottom: 1px solid var(--ws-line); }',
	'.ws-detail-row:last-child { border-bottom: 0; padding-bottom: 0; }',
	'.ws-detail-label { color: var(--ws-muted); font-size: 12px; }',
	'.ws-detail-value { font-weight: 650; overflow-wrap: anywhere; }',
	'.ws-detail-note { color: var(--ws-muted); font-size: 12px; margin-top: 2px; line-height: 1.35; }',
	'.ws-reason-list { margin: 0; padding-left: 18px; display: grid; gap: 7px; line-height: 1.5; }',
	'.ws-diagnostics-link { margin-top: 12px; }',
	'.ws-diagnostics-link a { color: var(--ws-info); font-weight: 650; }',
	'@media (max-width: 980px) { .ws-overview, .ws-secondary-grid, .ws-more-body { grid-template-columns: minmax(0, 1fr); } .ws-status-facts { grid-template-columns: repeat(2, minmax(0, 1fr)); } .ws-path { grid-template-columns: minmax(0, 1fr); } .ws-path-arrow { min-height: 10px; } }',
	'@media (max-width: 560px) { .wan-switch-title { align-items: flex-start; margin-bottom: 12px; } .wan-switch-title h2 { font-size: 21px; } .wan-switch-title p { display: none; } .ws-hero, .ws-card { padding: 14px; } .ws-hero h1 { font-size: 24px; } .ws-status-facts { grid-template-columns: minmax(0, 1fr); gap: 8px; } .ws-fact { padding: 8px 10px; } .ws-fact-value { font-size: 15px; } .ws-timeline { grid-template-columns: minmax(0, 1fr); } .ws-detail-row { grid-template-columns: minmax(0, 1fr); gap: 3px; } .ws-btn { width: 100%; } .ws-toolbar { width: 100%; } }'
].join('\n');

function statusUrl() {
	return L.url('admin/services/wan_switch/status') + '?_=' + Date.now();
}

function switchUrl(target) {
	return L.url('admin/services/wan_switch/switch') + '?target=' + encodeURIComponent(target) + '&_=' + Date.now();
}

function diagnosticsUrl() {
	return L.url('admin/services/wan_switch/diagnostics');
}

function parseJson(response) {
	if (!response || response.status >= 400)
		throw new Error('HTTP ' + (response ? response.status : 'error'));

	return response.json();
}

function fetchStatus() {
	return request.get(statusUrl(), { cache: false }).then(parseJson);
}

function text(value, fallback) {
	if (value === null || value === undefined || value === '')
		return fallback || '未知';

	return String(value);
}

function boolText(value) {
	return value ? '在线' : '离线';
}

function yesNo(value) {
	return value ? '会' : '不会';
}

function policyLabel(policy) {
	if (policy === 'campus_first')
		return '校园 WAN 优先';
	if (policy === 'f50_first')
		return 'F50 保护优先';
	return text(policy, '未知策略');
}

function riskLevel(status) {
	return status.risk_level || status.level || 'info';
}

function pill(label, level) {
	return E('span', { 'class': 'ws-pill ws-level-' + (level || 'neutral') }, label);
}

function showMessage(message, level) {
	if (!messageHost)
		return;

	messageHost.className = 'ws-message ws-level-' + (level || 'info');
	messageHost.textContent = message;
}

function clearMessage() {
	if (!messageHost)
		return;

	messageHost.className = 'ws-message is-hidden';
	messageHost.textContent = '';
}

function primaryAction(status) {
	if (status.outage_window && status.default_rule !== 'f50_first') {
		return {
			target: 'f50',
			label: status.f50_online ? '立即启用 F50 保护' : '预备 F50 保护',
			note: status.f50_online ? '当前处于断网保护窗口，建议把 mwan3 策略切到 F50 保护优先。' : 'F50 离线，仍可先预备策略；插入并获取 IP 后会接管。',
			level: status.f50_online ? 'danger' : 'warning',
			weak: !status.f50_online
		};
	}

	if (!status.outage_window && status.wan_online && status.default_rule !== 'campus_first') {
		return {
			target: 'campus',
			label: '恢复校园 WAN 优先',
			note: '当前不在断网窗口，校园 WAN 在线，建议恢复校园 WAN 作为主用出口。',
			level: 'success'
		};
	}

	if (status.recommended_policy !== status.default_rule) {
		return {
			target: 'auto',
			label: '按自动规则修复',
			note: '当前策略与推荐策略不一致，让脚本按工作日和时间窗口重新判断。',
			level: 'info'
		};
	}

	return {
		target: status.recommended_action || 'auto',
		label: status.recommended_action_label || '按自动规则检查',
		note: '当前策略基本符合自动规则，可手动触发一次检查确认状态。',
		level: 'info'
	};
}

function fact(label, value, note) {
	return E('div', { 'class': 'ws-fact' }, [
		E('div', { 'class': 'ws-fact-label' }, label),
		E('div', { 'class': 'ws-fact-value' }, value),
		note ? E('div', { 'class': 'ws-fact-note' }, note) : ''
	]);
}

function renderHero(status) {
	var level = riskLevel(status);
	var subtitle = text(status.current_exit, '未知出口') + ' · ' + policyLabel(status.default_rule);

	return E('section', { 'class': 'ws-hero ws-level-' + level, 'aria-live': 'polite' }, [
		E('div', { 'class': 'ws-hero-inner' }, [
			E('div', {}, [
				pill(text(status.risk_label, '状态信息'), level),
				E('h1', {}, text(status.headline, '网络状态未知')),
				E('div', { 'class': 'ws-hero-summary' }, subtitle),
				E('div', { 'class': 'ws-refresh-line' }, '最后刷新 ' + text(status.now, '-'))
			]),
			E('div', { 'class': 'ws-status-facts' }, [
				fact('实际出口', text(status.current_exit, '未知'), text(status.exit_ip, status.exit_note)),
				fact('当前策略', policyLabel(status.default_rule), text(status.protection_label, '-')),
				fact('下一步', text(status.next_action, '-'), text(status.window_label, '-'))
			])
		])
	]);
}

function nodeClass(role) {
	if (role === '当前出口')
		return ' is-current';
	if (role === '预备接管')
		return ' is-prepared';
	return '';
}

function renderPathNode(title, online, ip, role) {
	return E('div', { 'class': 'ws-path-node' + nodeClass(role) }, [
		E('div', { 'class': 'ws-node-head' }, [
			E('div', { 'class': 'ws-node-name' }, title),
			pill(boolText(online), online ? 'success' : 'danger')
		]),
		E('div', { 'class': 'ws-node-ip' }, text(ip, '未获取 IP')),
		pill(text(role, '待命'), role === '当前出口' ? 'success' : (role === '预备接管' ? 'info' : 'neutral'))
	]);
}

function renderPath(status) {
	var path = status.active_path || {};
	var campus = path.campus || {};
	var f50 = path.f50 || {};
	var policy = path.policy || {};

	return E('section', { 'class': 'ws-card' }, [
		E('h3', {}, '网络路径'),
		E('div', { 'class': 'ws-path' }, [
			renderPathNode('校园 WAN', campus.online !== undefined ? campus.online : status.wan_online, campus.ip || status.wan_ip, campus.role),
			E('div', { 'class': 'ws-path-arrow', 'aria-hidden': 'true' }, '→'),
			E('div', { 'class': 'ws-path-node ws-policy-node' }, [
				E('strong', {}, 'mwan3 策略'),
				E('div', {}, policyLabel(policy.value || status.default_rule)),
				pill((policy.matches_recommendation === false) ? '与推荐不一致' : '符合推荐', (policy.matches_recommendation === false) ? 'warning' : 'success')
			]),
			E('div', { 'class': 'ws-path-arrow', 'aria-hidden': 'true' }, '→'),
			renderPathNode('F50 USB', f50.online !== undefined ? f50.online : status.f50_online, f50.ip || status.f50_ip, f50.role)
		])
	]);
}

function renderTimeline(status) {
	var items = status.timeline_items || [];
	if (!items.length) {
		items = [
			{ label: '夜间切换', value: text(status.night_switch_label, '23:20'), state: 'idle', text: '按配置时间切到 F50' },
			{ label: '当前窗口', value: text(status.window_label, '-'), state: status.outage_window ? 'active' : 'idle', text: status.outage_window ? '保护窗口中' : '未进入保护窗口' },
			{ label: '早晨恢复', value: text(status.morning_switch_label, '07:50'), state: 'idle', text: '按配置时间恢复校园 WAN' }
		];
	}

	return E('section', { 'class': 'ws-card' }, [
		E('h3', {}, '自动策略时间轴'),
		E('p', { 'class': 'ws-card-subtle' }, text(status.window_label, '-') + ' · 明天' + (status.tomorrow_workday === 'yes' ? '是工作日' : '不是工作日或未知')),
		E('div', { 'class': 'ws-timeline' }, items.map(function(item) {
			return E('div', { 'class': 'ws-step ws-step-' + text(item.state, 'idle') }, [
				E('div', { 'class': 'ws-step-label' }, text(item.label, '-')),
				E('div', { 'class': 'ws-step-value' }, text(item.value, '-')),
				E('div', { 'class': 'ws-step-text' }, text(item.text, '-'))
			]);
		}))
	]);
}

function runSwitch(target) {
	if (busyTarget)
		return;

	busyTarget = target;
	if (stateHost)
		stateHost.setAttribute('aria-busy', 'true');

	showMessage('正在执行切换：' + actionLabel(target) + '...', 'info');
	render();

	request.get(switchUrl(target), { cache: false }).then(parseJson).then(function(result) {
		busyTarget = null;
		currentStatus = result.status || currentStatus;

		if (stateHost)
			stateHost.setAttribute('aria-busy', 'false');

		showMessage(result.message || (result.success ? '切换完成' : '切换失败'), result.success ? 'success' : 'danger');
		render();
		return fetchStatus();
	}).then(function(status) {
		currentStatus = status;
		render();
	}).catch(function(error) {
		busyTarget = null;
		if (stateHost)
			stateHost.setAttribute('aria-busy', 'false');

		showMessage('切换失败：' + (error.message || error), 'danger');
		render();
	});
}

function actionLabel(target) {
	if (target === 'campus')
		return '切到校园 WAN';
	if (target === 'f50')
		return '切到 F50';
	return '按自动规则切换';
}

function actionButton(target, label, primary, level, weak) {
	var classes = 'ws-btn' + (primary ? ' ws-primary ws-level-' + (level || 'info') : '') + (weak ? ' weak' : '');
	var busy = busyTarget === target;
	var attrs = {
		'class': classes,
		'type': 'button',
		'aria-label': label,
		'click': function(ev) {
			ev.preventDefault();
			runSwitch(target);
		}
	};

	if (busyTarget)
		attrs.disabled = 'disabled';

	return E('button', attrs, busy ? '执行中...' : label);
}

function renderActions(status) {
	var primary = primaryAction(status);
	var targets = [
		{ target: 'campus', label: '切到校园 WAN' },
		{ target: 'f50', label: status.f50_online ? '切到 F50' : '预备 F50' },
		{ target: 'auto', label: '按自动规则切换' }
	];

	return E('section', { 'class': 'ws-card' }, [
		E('h3', {}, '推荐操作'),
		E('div', { 'class': 'ws-action-layout' }, [
			E('div', { 'class': 'ws-primary-action' }, [
				E('div', { 'class': 'ws-action-title' }, primary.label),
				E('div', { 'class': 'ws-action-note' }, primary.note),
				actionButton(primary.target, primary.label, true, primary.level, primary.weak)
			]),
			E('div', {}, [
				E('div', { 'class': 'ws-action-note', 'style': 'margin-bottom:8px' }, '其他操作'),
				E('div', { 'class': 'ws-button-row' }, targets.filter(function(item) {
					return item.target !== primary.target;
				}).map(function(item) {
					return actionButton(item.target, item.label, false, null, item.target === 'f50' && !status.f50_online);
				}))
			])
		])
	]);
}

function detailRow(label, value, note) {
	return E('div', { 'class': 'ws-detail-row' }, [
		E('div', { 'class': 'ws-detail-label' }, label),
		E('div', {}, [
			E('div', { 'class': 'ws-detail-value' }, value),
			note ? E('div', { 'class': 'ws-detail-note' }, note) : ''
		])
	]);
}

function renderMoreDetails(status) {
	var lines = status.reason_lines || [];
	if (!lines.length)
		lines = [ '状态接口还没有返回判断链。' ];

	return E('details', { 'class': 'ws-more' }, [
		E('summary', {}, [
			E('span', {}, '更多状态与判断依据')
		]),
		E('div', { 'class': 'ws-more-body' }, [
			E('div', { 'class': 'ws-more-panel' }, [
				E('h3', {}, '状态细节'),
				E('div', { 'class': 'ws-detail-rows' }, [
					detailRow('今晚断网', yesNo(status.outage_tonight), text(status.window_label, '-')),
					detailRow('保护状态', text(status.protection_label, '-'), text(status.exit_note, '-')),
					detailRow('WAN / F50', (status.wan_online ? 'WAN 在线' : 'WAN 离线') + ' · ' + (status.f50_online ? 'F50 在线' : 'F50 离线'), text(status.wan_ip, '-') + ' / ' + text(status.f50_ip, '-')),
					detailRow('诊断摘要', text(status.diagnostics_summary, '-'), null)
				])
			]),
			E('div', { 'class': 'ws-more-panel' }, [
				E('h3', {}, '判断依据'),
				E('ol', { 'class': 'ws-reason-list' }, lines.map(function(line) {
					return E('li', {}, line);
				})),
				E('div', { 'class': 'ws-diagnostics-link' }, [
					E('a', { 'href': diagnosticsUrl() }, '打开诊断页')
				])
			])
		])
	]);
}

function renderDashboard(status) {
	return E('div', { 'class': 'ws-grid' }, [
		E('div', { 'class': 'ws-overview' }, [
			renderHero(status),
			renderActions(status)
		]),
		renderPath(status),
		E('div', { 'class': 'ws-secondary-grid' }, [
			renderTimeline(status),
			renderMoreDetails(status)
		])
	]);
}

function replaceChildren(node, child) {
	while (node.firstChild)
		node.removeChild(node.firstChild);

	node.appendChild(child);
}

function render() {
	if (!stateHost)
		return;

	replaceChildren(stateHost, currentStatus ? renderDashboard(currentStatus) : E('div', { 'class': 'ws-card' }, '正在加载状态...'));
}

function startPolling() {
	if (pollStarted)
		return;

	pollStarted = true;
	poll.add(function() {
		return fetchStatus().then(function(status) {
			currentStatus = status;
			if (messageHost && messageHost.textContent.indexOf('状态刷新失败') === 0)
				clearMessage();
			render();
		}).catch(function(error) {
			showMessage('状态刷新失败，正在重试：' + (error.message || error), 'warning');
		});
	}, 5);
}

return view.extend({
	load: function() {
		return fetchStatus().catch(function(error) {
			return { load_error: error.message || String(error) };
		});
	},

	render: function(data) {
		currentStatus = data && !data.load_error ? data : currentStatus;

		stateHost = E('div', { 'class': 'ws-state', 'aria-live': 'polite' });
		messageHost = E('div', { 'class': data && data.load_error ? 'ws-message ws-level-warning' : 'ws-message is-hidden', 'aria-live': 'assertive' }, data && data.load_error ? ('状态加载失败，正在重试：' + data.load_error) : '');

		var root = E('div', { 'class': 'wan-switch-console' }, [
			E('style', {}, STYLE),
			E('div', { 'class': 'wan-switch-title' }, [
				E('div', {}, [
					E('h2', {}, 'WAN/F50 网络保障控制台'),
					E('p', {}, '自动保障夜间和早晨断网窗口，手动操作会保留后端现有切换逻辑。')
				])
			]),
			messageHost,
			stateHost
		]);

		render();
		startPolling();

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
