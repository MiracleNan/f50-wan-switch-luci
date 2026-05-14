'use strict';
'require view';
'require request';
'require poll';
'require ui';

var diagnosticsHost = null;
var messageHost = null;
var currentDiagnostics = null;
var pollStarted = false;

var STYLE = [
	':root { --wd-surface: #ffffff; --wd-text: #172033; --wd-muted: #647084; --wd-line: #dce3ee; --wd-soft: #eef3f8; --wd-success: #16845b; --wd-danger: #c4362e; --wd-info: #2563a8; --wd-warning: #9a6500; --wd-shadow: 0 8px 24px rgba(18, 32, 52, .06); }',
	'.wan-switch-diag { color: var(--wd-text); max-width: 1160px; margin: 0 auto; overflow-x: hidden; }',
	'.wan-switch-diag * { box-sizing: border-box; min-width: 0; }',
	'.wd-title { display: flex; justify-content: space-between; align-items: flex-end; gap: 14px; flex-wrap: wrap; margin-bottom: 14px; }',
	'.wd-title h2 { margin: 0; font-size: 24px; line-height: 1.25; }',
	'.wd-title p { margin: 6px 0 0; color: var(--wd-muted); }',
	'.wd-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }',
	'.wd-card { background: var(--wd-surface); border: 1px solid var(--wd-line); border-radius: 12px; padding: 14px; box-shadow: var(--wd-shadow); }',
	'.wd-card h3 { margin: 0 0 10px; font-size: 16px; line-height: 1.35; }',
	'.wd-card.full { grid-column: 1 / -1; }',
	'.wd-message { border: 1px solid var(--wd-line); border-radius: 10px; padding: 10px 12px; margin-bottom: 12px; background: var(--wd-soft); color: var(--wd-text); }',
	'.wd-message.is-hidden { display: none; }',
	'.wd-message.warning { color: var(--wd-warning); background: #fff4d8; border-color: rgba(154, 101, 0, .25); }',
	'.wd-pill { display: inline-flex; border-radius: 999px; padding: 4px 9px; font-size: 12px; font-weight: 650; background: var(--wd-soft); color: var(--wd-muted); }',
	'.wd-pill.success { color: var(--wd-success); background: #e6f6ef; }',
	'.wd-pill.danger { color: var(--wd-danger); background: #fdebea; }',
	'.wd-pill.info { color: var(--wd-info); background: #e8f1fb; }',
	'.wd-kv { display: grid; grid-template-columns: minmax(110px, .36fr) minmax(0, 1fr); gap: 8px 12px; line-height: 1.45; }',
	'.wd-kv span:nth-child(odd) { color: var(--wd-muted); }',
	'.wd-kv span:nth-child(even) { overflow-wrap: anywhere; }',
	'.wd-pre { margin: 0; max-height: 360px; overflow: auto; white-space: pre-wrap; word-break: break-word; border-radius: 10px; background: #101827; color: #e8edf6; padding: 12px; font-size: 12px; line-height: 1.45; }',
	'.wd-toolbar { display: flex; gap: 8px; flex-wrap: wrap; }',
	'.wd-btn { appearance: none; border: 1px solid var(--wd-line); border-radius: 10px; background: var(--wd-surface); color: var(--wd-text); padding: 9px 12px; font-weight: 650; cursor: pointer; text-decoration: none; }',
	'.wd-btn:hover { background: var(--wd-soft); }',
	'@media (max-width: 760px) { .wd-grid { grid-template-columns: minmax(0, 1fr); } .wd-kv { grid-template-columns: minmax(0, 1fr); } .wd-btn { width: 100%; text-align: center; } .wd-toolbar { width: 100%; } }'
].join('\n');

function dataUrl() {
	return L.url('admin/services/wan_switch/diagnostics_status') + '?_=' + Date.now();
}

function mainUrl() {
	return L.url('admin/services/wan_switch');
}

function parseJson(response) {
	if (!response || response.status >= 400)
		throw new Error('HTTP ' + (response ? response.status : 'error'));

	return response.json();
}

function fetchDiagnostics() {
	return request.get(dataUrl(), { cache: false }).then(parseJson);
}

function text(value, fallback) {
	if (value === null || value === undefined || value === '')
		return fallback || '未知';

	return String(value);
}

function pill(label, ok) {
	return E('span', { 'class': 'wd-pill ' + (ok ? 'success' : 'danger') }, label);
}

function kv(items) {
	var children = [];
	items.forEach(function(item) {
		children.push(E('span', {}, item[0]));
		children.push(E('span', {}, item[1]));
	});
	return E('div', { 'class': 'wd-kv' }, children);
}

function lines(list) {
	if (!list || !list.length)
		return '暂无输出';

	return list.join('\n');
}

function showMessage(message) {
	if (!messageHost)
		return;

	messageHost.className = 'wd-message warning';
	messageHost.textContent = message;
}

function clearMessage() {
	if (!messageHost)
		return;

	messageHost.className = 'wd-message is-hidden';
	messageHost.textContent = '';
}

function renderIface(title, data) {
	data = data || {};

	return E('section', { 'class': 'wd-card' }, [
		E('h3', {}, title),
		E('div', { 'style': 'margin-bottom:10px' }, pill(data.up ? '在线' : '离线', data.up)),
		kv([
			[ '协议', text(data.proto, '-') ],
			[ '设备', text(data.device || data.l3_device, '-') ],
			[ 'IP', text(data.ip, '未获取') ],
			[ '网关', text(data.gateway, '-') ]
		])
	]);
}

function renderDiagnostics(data) {
	var status = data.status || {};
	var ifstatus = data.ifstatus || {};
	var workday = data.workday || {};
	var cache = data.cache || {};
	var portal = data.portal || {};

	return E('div', { 'class': 'wd-grid' }, [
		E('section', { 'class': 'wd-card full' }, [
			E('h3', {}, '状态摘要'),
			kv([
				[ '生成时间', text(data.generated_at, '-') ],
				[ '当前出口', text(status.current_exit, '-') ],
				[ '当前策略', text(status.policy_label, '-') ],
				[ '推荐策略', text(status.recommended_policy, '-') ],
				[ '下一步', text(status.next_action, '-') ],
				[ '风险', text(status.risk_label || status.level, '-') ]
			])
		]),
		renderIface('WAN ifstatus', ifstatus.wan),
		renderIface('F50 ifstatus', ifstatus.f50),
		E('section', { 'class': 'wd-card' }, [
			E('h3', {}, '工作日与缓存'),
			kv([
				[ '今天', text(workday.today, '-') + ' · ' + text(workday.today_workday, '-') + ' · ' + text(workday.today_source, '-') ],
				[ '明天', text(workday.tomorrow, '-') + ' · ' + text(workday.tomorrow_workday, '-') + ' · ' + text(workday.tomorrow_source, '-') ],
				[ '缓存目录', cache.exists ? '存在' : '不存在' ],
				[ '缓存文件', cache.files && cache.files.length ? cache.files.join(', ') : '暂无' ]
			])
		]),
		E('section', { 'class': 'wd-card' }, [
			E('h3', {}, '校园门户认证'),
			kv([
				[ '配置文件', portal.config_present ? '存在' : '不存在' ],
				[ '认证命令', portal.login_configured ? '已配置' : '未配置' ],
				[ '说明', text(portal.note, '不会显示真实登录 URL') ]
			])
		]),
		E('section', { 'class': 'wd-card full' }, [
			E('h3', {}, 'mwan3 status 摘要'),
			E('pre', { 'class': 'wd-pre' }, lines(data.mwan3_summary))
		]),
		E('section', { 'class': 'wd-card full' }, [
			E('h3', {}, '脚本状态输出'),
			E('pre', { 'class': 'wd-pre' }, lines(data.script_status))
		]),
		E('section', { 'class': 'wd-card full' }, [
			E('h3', {}, '最近 f50-wan-switch 日志'),
			E('pre', { 'class': 'wd-pre' }, lines(data.recent_logs))
		])
	]);
}

function replaceChildren(node, child) {
	while (node.firstChild)
		node.removeChild(node.firstChild);

	node.appendChild(child);
}

function render() {
	if (!diagnosticsHost)
		return;

	replaceChildren(diagnosticsHost, currentDiagnostics ? renderDiagnostics(currentDiagnostics) : E('section', { 'class': 'wd-card' }, '正在加载诊断信息...'));
}

function refreshDiagnostics() {
	return fetchDiagnostics().then(function(data) {
		currentDiagnostics = data;
		if (messageHost && messageHost.textContent.indexOf('诊断刷新失败') === 0)
			clearMessage();
		render();
	}).catch(function(error) {
		showMessage('诊断刷新失败，正在重试：' + (error.message || error));
	});
}

function startPolling() {
	if (pollStarted)
		return;

	pollStarted = true;
	poll.add(refreshDiagnostics, 5);
}

return view.extend({
	load: function() {
		return fetchDiagnostics().catch(function(error) {
			return { load_error: error.message || String(error) };
		});
	},

	render: function(data) {
		currentDiagnostics = data && !data.load_error ? data : currentDiagnostics;
		messageHost = E('div', { 'class': data && data.load_error ? 'wd-message warning' : 'wd-message is-hidden', 'aria-live': 'assertive' }, data && data.load_error ? ('诊断加载失败，正在重试：' + data.load_error) : '');
		diagnosticsHost = E('div', { 'aria-live': 'polite' });

		var root = E('div', { 'class': 'wan-switch-diag' }, [
			E('style', {}, STYLE),
			E('div', { 'class': 'wd-title' }, [
				E('div', {}, [
					E('h2', {}, 'WAN/F50 诊断'),
					E('p', {}, '只读诊断信息，不触发认证、不改变 mwan3 策略，也不会显示真实登录 URL。')
				]),
				E('div', { 'class': 'wd-toolbar' }, [
					E('a', { 'class': 'wd-btn', 'href': mainUrl(), 'aria-label': '返回控制台' }, '返回控制台'),
					E('button', { 'class': 'wd-btn', 'type': 'button', 'aria-label': '刷新诊断', 'click': function(ev) { ev.preventDefault(); refreshDiagnostics(); } }, '刷新')
				])
			]),
			messageHost,
			diagnosticsHost
		]);

		render();
		startPolling();

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
