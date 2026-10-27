'use strict';
'require view';
'require poll';

var ST = { tab: 'sources', range: '24h', page: 1, size: 15, proto: 'all', only: 'watch', total: 0 };

var CSS = [
'.guard{--line:#e9ecf2;--soft:#f2f4f8;--txt:#1f2430;--mute:#79808f;--main:#5e72e4;--navy:#33409c;--row:33px;--head:32px;--sh:0 1px 2px rgba(17,24,39,.04),0 2px 8px rgba(17,24,39,.04);display:flex;flex-direction:column;font-size:13px;line-height:1.5;color:var(--txt)}',
// Argon 给 #view 的第一个 div 塞了 gap:.875rem，三块各多 14px。这里按同特异性覆盖掉。
// #view 高度是 auto，height:100% 拉不动，所以直接把 #view 变成撑满视口的 flex 列，
// 让面板吃掉剩余高度：矮屏不会把分页器顶出视口，数据少时也不会在底部留一大片灰。
// 这里的高度只是兜底，实际值由 fitView() 按 header/footer 实测高度写入（见 render 末尾）。
'#view{display:flex;flex-direction:column;height:calc(100vh - 115px)}',
'#view > div.guard{flex:1 1 auto;min-height:0;gap:0}',
// 和 OpenClash / Lucky 一致：内容从 header 底边直接起，第一张卡压住那条 32px 蓝色装饰带。
// Argon 写的是 .main-right > #maincontent > .container（比我多一个 class），所以这里重复 class 提特异性。
'#maincontent > .container.container{margin-bottom:0}',
'.guard .g-hd{background:#fff;border:1px solid var(--line);border-radius:10px;padding:6px 16px 8px;margin:0 0 10px;flex:none;box-shadow:var(--sh)}',
'.guard .g-hd-top{display:flex;align-items:center;gap:10px;min-width:0}',
'.guard .g-title{font-size:19px;font-weight:600;letter-spacing:.01em;line-height:1.35;margin:0;padding:0;background:none;border:0;box-shadow:none;white-space:nowrap;color:var(--navy)}',
'.guard .g-updated{font-size:12px;color:var(--mute);white-space:nowrap;flex:none;margin-left:auto}',
'.guard .g-meta{display:flex;align-items:center;flex-wrap:wrap;gap:2px 12px;font-size:12.5px;color:var(--mute);margin:2px 0 0;min-height:19px}',
'.guard .g-mi{display:inline-flex;align-items:center;white-space:nowrap;max-width:100%}',
'.guard .g-exposed{overflow:hidden;text-overflow:ellipsis}',
'.guard .g-cover{color:#9a6a1f}',
'.guard .g-pill{display:inline-flex;align-items:center;gap:5px;background:#e9f7ef;color:#1f7a4d;border-radius:999px;padding:1px 9px 1px 8px;font-size:12px;font-weight:500;white-space:nowrap;flex:none}',
'.guard .g-pill.err{background:#fdecec;color:#c33333}',
'.guard .g-dot{display:inline-block;width:6px;height:6px;border-radius:50%;background:#22a06b;flex:none;animation:g-pulse 2.4s ease-in-out infinite}',
'@keyframes g-pulse{0%,100%{opacity:1}50%{opacity:.35}}',
'.guard .g-dot.err{background:#d64545;animation:none}',
'.guard .g-cards{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;flex:none;margin:0 0 10px}',
'.guard .g-card{position:relative;background:#fff;border:1px solid var(--line);border-radius:10px;padding:7px 14px 8px 17px;overflow:hidden;box-shadow:var(--sh)}',
'.guard .g-card::before{content:"";position:absolute;left:0;top:0;bottom:0;width:3px;background:var(--ac,#5e72e4)}',
'.guard .g-card .k{color:var(--mute);font-size:12px;line-height:1.5;letter-spacing:.01em}',
'.guard .g-card .v{margin-top:1px;font-size:22px;font-weight:600;line-height:1.3;font-variant-numeric:tabular-nums;letter-spacing:-.01em}',
'.guard .g-card .s{margin-top:0;color:#8b93a1;font-size:11.5px;line-height:1.45;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
'.guard .g-panel{background:#fff;border:1px solid var(--line);border-radius:10px;overflow:hidden;flex:1 1 auto;min-height:0;display:flex;flex-direction:column;box-shadow:var(--sh)}',
'.guard .g-tabs{display:flex;gap:2px;padding:3px 8px;border-bottom:1px solid var(--line);flex:none}',
'.guard .g-tab{padding:3px 13px;border-radius:7px;cursor:pointer;font-size:13px;line-height:1.5;color:var(--mute);transition:background .15s,color .15s;-webkit-user-select:none;user-select:none}',
'.guard .g-tab:hover{background:#f4f6fa;color:var(--txt)}',
'.guard .g-tab.on{background:#eef1fe;color:#3f56d6;font-weight:600}',
'.guard .g-bar{display:flex;align-items:center;gap:8px;padding:0 14px;height:36px;border-bottom:1px solid var(--soft);flex:none}',
'.guard .g-bar select{height:26px;line-height:1;font-size:12.5px;padding:0 8px;border:1px solid var(--line);border-radius:6px;background:#fff;color:var(--txt);min-height:0}',
'.guard .g-bar .sp{flex:1}',
'.guard .g-bar .muted{color:var(--mute);font-size:12.5px}',
// 数据不足时下面留白，只由最后一条数据的下边框收尾，不再逐行画分隔线
'.guard .g-tw{flex:1 1 auto;min-height:calc(8*var(--row) + var(--head));overflow:auto}',
'.guard .g-table{width:100%;min-width:840px;margin:0;border:0;border-collapse:collapse;table-layout:fixed;background:none;box-shadow:none}',
'.guard .g-table th,.guard .g-table td{padding:0 12px;border:0;border-bottom:1px solid var(--soft);text-align:left;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;background:none}',
'.guard .g-table th{height:var(--head);font-size:12px;font-weight:600;letter-spacing:.02em;color:#6b7280;background:#f2f4f8;position:sticky;top:0;z-index:1}',
'.guard .g-tw::-webkit-scrollbar{width:9px;height:9px}',
'.guard .g-tw::-webkit-scrollbar-thumb{background:#d5dae4;border-radius:5px;border:2px solid #fff}',
'.guard .g-tw::-webkit-scrollbar-thumb:hover{background:#c2c9d6}',
'.guard .g-tw::-webkit-scrollbar-track{background:transparent}',
'.guard .g-tw{scrollbar-width:thin;scrollbar-color:#d5dae4 transparent}',
'.guard .g-table td{height:var(--row)}',
'.guard .g-table tbody tr{background:#fff}',
'.guard .g-table tbody tr:nth-child(even){background:#f7f8fb}',
'.guard .g-table tbody tr:hover{background:#eef3ff}',
'.guard .g-table tbody tr:last-child td{border-bottom:1px solid var(--soft)}',
'.guard .g-table .num{text-align:center;font-variant-numeric:tabular-nums}',
'.guard .g-num0{color:#b3bac6}',
'.guard .g-watch{color:#d64545;font-weight:600}',
'.guard .g-time{color:var(--mute);font-variant-numeric:tabular-nums}',
'.guard .g-ip{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12.5px;letter-spacing:-.01em}',
'.guard .g-geo{color:#5c6474;font-size:12px}',
'.guard .g-host{color:#334155;font-size:12.5px}',
'.guard .g-proto{color:var(--mute);font-size:12px;letter-spacing:.03em;text-transform:uppercase}',
'.guard .g-tag{display:inline-block;padding:0 8px;border-radius:999px;font-size:11.5px;line-height:18px;font-weight:500;max-width:100%;overflow:hidden;text-overflow:ellipsis;vertical-align:middle}',
'.guard .g-tag.scan{background:#fdecec;color:#d64545}',
'.guard .g-tag.rate{background:#fdf3e3;color:#bf7212}',
'.guard .g-tag.l{background:#fdecec;color:#c33333}',
'.guard .g-tag.p{background:#fdf3e3;color:#b45309}',
'.guard .g-tag.u{background:#eef2ff;color:#4f5bd5}',
'.guard .g-tag.b{background:#f1f3f6;color:#64748b}',
'.guard .g-tag.n{background:#f1f3f6;color:#94a3b8}',
'.guard .g-dash{color:#ccd1db}',
'.guard .g-self{color:#5c6474;font-size:12px}',
'.guard .g-table td.g-empty{height:auto;padding:0}',
'.guard .g-empty>div{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:9px;height:180px;color:#a7aeba;font-size:13px}',
'.guard .g-empty svg{opacity:.55}',
'.guard .g-pager{display:flex;align-items:center;gap:8px;padding:0 14px;height:36px;border-top:1px solid var(--soft);color:var(--mute);font-size:12.5px;flex:none}',
'.guard .g-pager .sp{flex:1}',
'.guard .g-pager .pg{color:#4b5563;font-variant-numeric:tabular-nums}',
'.guard .g-pager button{height:26px;line-height:1;font-size:12.5px;padding:0 11px;border:1px solid var(--line);border-radius:6px;background:#fff;color:var(--txt);cursor:pointer;min-height:0;transition:background .15s,border-color .15s,color .15s}',
'.guard .g-pager button:hover:not(:disabled){border-color:#c3cbf0;background:#f6f8ff;color:#3f56d6}',
'.guard .g-pager button:disabled{opacity:.4;cursor:default}',
'.guard .g-empty-note{color:#9aa1ae}',
'@media(max-height:880px){.guard{--row:31px}}',
'@media(max-height:820px){.guard{--row:29px}}',
'@media(max-width:1240px){.guard .g-table th,.guard .g-table td{padding:0 8px}}',
'@media(max-width:900px){.guard .g-cards{grid-template-columns:repeat(2,1fr)}}',
'@media(max-width:560px){.guard .g-updated{display:none}.guard .g-hd-top{flex-wrap:wrap}}'
].join('\n');

function esc(s) {
	return String(s == null ? '' : s).replace(/[&<>"]/g, function(c) {
		return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
	});
}

function api(qs) {
	return fetch('/cgi-bin/guard?' + qs, { cache: 'no-store' }).then(function(r) { return r.json(); });
}

var COLS = {
	sources: [['来源 IP', 19, 0], ['归属地', 24, 0], ['主要落点', 14, 0], ['连接数', 7, 1], ['TCP', 5, 1], ['UDP', 5, 1], ['公网命中', 7, 1], ['最近', 19, 0]],
	ports:   [['落点', 24, 0], ['端口', 9, 1], ['类型', 26, 0], ['协议', 7, 0], ['来源数', 10, 1], ['连接数', 8, 1], ['最近', 16, 0]],
	alerts:  [['时间', 18, 0], ['类型', 10, 0], ['来源 IP', 15, 0], ['归属地', 22, 0], ['连接数', 6, 1], ['端口', 29, 0]],
	events:  [['时间', 14, 0], ['来源 IP', 15, 0], ['归属地', 17, 0], ['落点', 13, 0], ['端口', 7, 1], ['协议', 6, 0], ['类型', 28, 0]]
};

var EMPTY_ICON = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" ' +
	'stroke-linecap="round"><path d="M3.5 6h17M3.5 12h17M3.5 18h17"/>' +
	'<circle cx="7.5" cy="6" r="1.3" fill="currentColor" stroke="none"/>' +
	'<circle cx="7.5" cy="12" r="1.3" fill="currentColor" stroke="none"/>' +
	'<circle cx="7.5" cy="18" r="1.3" fill="currentColor" stroke="none"/></svg>';

function emptyRow(cols, text) {
	return '<tr><td class="g-empty" colspan="' + cols + '"><div>' + EMPTY_ICON +
		'<span class="g-empty-note">' + esc(text) + '</span></div></td></tr>';
}

function cellNum(v) {
	return '<td class="num' + (v ? '' : ' g-num0') + '">' + v + '</td>';
}

function geoText(x) {
	var place = (x.country || '') + (x.region ? '·' + x.region : '');
	var isp = x.isp || '';
	if (!place && !isp) return '';
	return (place + (isp ? ' ' + isp : '')).trim();
}

function cellGeo(x) {
	var full = [x.country, x.region, x.isp].filter(function(v) { return v; }).join(' ');
	if (!full) return '<td class="g-dash">—</td>';
	return '<td class="g-geo" title="' + esc(full) + '">' + esc(geoText(x)) + '</td>';
}

// 落点：有设备名显示名字，没名字显示 IP；悬浮统一给「名字 · IP」
function cellHost(host, ip) {
	if (!host && !ip) return '<td class="g-dash" title="无落点记录">—</td>';
	if (!host) return '<td class="g-ip" title="' + esc(ip) + '">' + esc(ip) + '</td>';
	if (host === ip) return '<td class="g-ip" title="' + esc(ip) + '">' + esc(ip) + '</td>';
	return '<td class="g-host" title="' + esc(host + (ip ? ' · ' + ip : '')) + '">' + esc(host) + '</td>';
}

// 事件流的落点：路由器自身统一显示“路由器”，悬浮带上 LAN/WAN 地址
function cellDev(host, ip) {
	if (ip && ip === ST.wan) return '<td title="路由器 · 192.168.1.1（WAN ' + esc(ip) + '）">' +
		'<span class="g-self">路由器</span></td>';
	if (host && host !== ip) return '<td class="g-host" title="' + esc(ip) + '">' + esc(host) + '</td>';
	if (ip) return '<td class="g-ip" title="' + esc(ip) + '">' + esc(ip) + '</td>';
	return '<td class="g-dash" title="无落点记录">—</td>';
}

function classTag(c, desc) {
	if (c === 'L') return '<span class="g-tag l">公网服务</span>';
	if (c === 'P') return '<span class="g-tag p" title="未映射到内机">未落地</span>';
	if (c === 'U') return '<span class="g-tag u" title="' + esc(desc || '') + '">UPnP' + (desc ? ' · ' + esc(desc) : '') + '</span>';
	if (c === 'B') return '<span class="g-tag b">内机回连</span>';
	if (c === 'N') return '<span class="g-tag n">已忽略</span>';
	return '<span class="g-dash">—</span>';
}

function rowHTML(tab, x) {
	if (tab === 'sources')
		return '<tr><td class="g-ip" title="' + esc(x.ip) + '">' + esc(x.ip) + '</td>' +
			cellGeo(x) + cellHost(x.host, x.dst) +
			cellNum(x.total) + cellNum(x.tcp) + cellNum(x.udp) +
			'<td class="num' + (x.watch ? ' g-watch' : ' g-num0') + '">' + x.watch + '</td>' +
			'<td class="g-time">' + esc(x.last) + '</td></tr>';
	if (tab === 'ports')
		return '<tr>' + cellHost(x.host, x.dst) +
			cellNum(x.dport) +
			'<td title="' + esc(x.desc || '') + '">' + classTag(x.class, x.desc) + '</td>' +
			'<td class="g-proto">' + esc(x.proto) + '</td>' +
			cellNum(x.srcs) + cellNum(x.count) +
			'<td class="g-time">' + esc(x.last) + '</td></tr>';
	if (tab === 'alerts') {
		var t = x.type === 'PORT_SCAN' ? '<span class="g-tag scan">端口扫描</span>' :
			x.type === 'HIGH_RATE' ? '<span class="g-tag rate">高频连接</span>' : esc(x.type);
		return '<tr><td class="g-time">' + esc(x.t) + '</td><td>' + t + '</td>' +
			'<td class="g-ip" title="' + esc(x.ip) + '">' + esc(x.ip) + '</td>' + cellGeo(x) +
			cellNum(x.count) +
			'<td title="' + esc(x.ports) + '">' + esc(x.ports) + '</td></tr>';
	}
	return '<tr><td class="g-time">' + esc(x.t) + '</td>' +
		'<td class="g-ip" title="' + esc(x.ip) + '">' + esc(x.ip) + '</td>' + cellGeo(x) +
		cellDev(x.host, x.dst) +
		cellNum(x.dport) +
		'<td class="g-proto">' + esc(x.proto) + '</td>' +
		'<td title="' + esc(x.desc || '') + '">' + classTag(x.class, '') + '</td></tr>';
}

// 对外端口：把连续端口合并成区间（55508 55509 -> 55508-55509），
// 超过 MAX 段再折叠成 +N。原始列表由 dnsmasq 的 dport 排序输出，但可能重复/乱序，先规范化。
var EXPOSED_MAX = 10;

function aggPorts(s) {
	var arr = String(s || '').replace(/[,\s]+/g, ' ').trim().split(' ')
		.map(function(v) { return parseInt(v, 10); })
		.filter(function(n) { return n > 0 && n < 65536; });
	if (!arr.length) return [];

	arr.sort(function(a, b) { return a - b; });

	var uniq = [];
	for (var i = 0; i < arr.length; i++)
		if (!i || arr[i] !== arr[i - 1]) uniq.push(arr[i]);

	var out = [], st = uniq[0], en = uniq[0];
	for (var j = 1; j < uniq.length; j++) {
		if (uniq[j] === en + 1) { en = uniq[j]; continue; }
		out.push(st === en ? String(st) : st + '-' + en);
		st = en = uniq[j];
	}
	out.push(st === en ? String(st) : st + '-' + en);
	return out;
}

function fmtExposed(s) {
	var segs = aggPorts(s);
	if (!segs.length) return { text: '', title: '' };
	return {
		text: segs.length > EXPOSED_MAX
			? segs.slice(0, EXPOSED_MAX).join(' ') + ' +' + (segs.length - EXPOSED_MAX)
			: segs.join(' '),
		title: segs.length > EXPOSED_MAX ? segs.join(' ') : ''
	};
}

function fmtSpan(min) {
	min = parseInt(min, 10) || 0;
	if (min >= 60) return Math.floor(min / 60) + ' 小时 ' + (min % 60) + ' 分';
	return min + ' 分';
}

return view.extend({
	render: function() {
		var refs = {};

		refs.stat = E('span', { 'class': 'g-pill' }, [
			refs.dot = E('span', { 'class': 'g-dot' }),
			refs.status = E('span', {}, '连接中…')
		]);

		refs.updated = E('span', { 'class': 'g-updated' }, '');

		refs.wan = E('span', { 'class': 'g-mi' }, '');
		refs.uptime = E('span', { 'class': 'g-mi' }, '');
		refs.exposed = E('span', { 'class': 'g-mi g-exposed' }, '');
		refs.cover = E('span', { 'class': 'g-mi g-cover' }, '');

		// 标题 + 状态 + 更新时间 + 环境信息，收进一张标准白卡里
		var head = E('div', { 'class': 'g-hd' }, [
			E('div', { 'class': 'g-hd-top' }, [
				E('div', { 'class': 'g-title' }, '外部访问监控'),
				refs.stat,
				refs.updated
			]),
			E('div', { 'class': 'g-meta' }, [refs.wan, refs.uptime, refs.exposed, refs.cover])
		]);

		function card(k, id, color) {
			var v = E('div', { 'class': 'v' }, '–');
			var s = E('div', { 'class': 's' }, '');
			refs[id] = v;
			refs[id + '-s'] = s;
			return E('div', { 'class': 'g-card', 'style': '--ac:' + color }, [
				E('div', { 'class': 'k' }, k), v, s
			]);
		}

		var cards = E('div', { 'class': 'g-cards' }, [
			card('24 小时连接', 'c-conn', '#5e72e4'),
			card('24 小时来源 IP', 'c-ips', '#11a5a0'),
			card('关注连接', 'c-watch', '#d64545'),
			card('24 小时告警', 'c-alerts', '#e8833a')
		]);

		refs.tabs = E('div', { 'class': 'g-tabs' });
		[['sources', '来源 IP'], ['ports', '暴露面'], ['alerts', '告警事件'], ['events', '最近连接']].forEach(function(p) {
			var attrs = {
				'class': 'g-tab' + (p[0] === ST.tab ? ' on' : ''),
				'data-tab': p[0],
				'click': function() { switchTab(p[0]); }
			};
			if (p[0] === 'ports')
				attrs.title = '公网服务与 UPnP 端口清单，含 24 小时无流量的端口';
			refs.tabs.appendChild(E('div', attrs, p[1]));
		});

		refs.range = E('select', { 'change': function(ev) { ST.range = ev.target.value; ST.page = 1; loadList(); } }, [
			E('option', { 'value': '24h', 'selected': ST.range === '24h' ? 'selected' : null }, '24 小时'),
			E('option', { 'value': '7d', 'selected': ST.range === '7d' ? 'selected' : null }, '7 天'),
			E('option', { 'value': '30d', 'selected': ST.range === '30d' ? 'selected' : null }, '30 天')
		]);
		refs.proto = E('select', { 'change': function(ev) { ST.proto = ev.target.value; ST.page = 1; loadList(); } }, [
			E('option', { 'value': 'tcp', 'selected': ST.proto === 'tcp' ? 'selected' : null }, '仅 TCP'),
			E('option', { 'value': 'all', 'selected': ST.proto === 'all' ? 'selected' : null }, '全部协议')
		]);
		refs.only = E('select', {
			title: '切到“含正常流量”会自动选择全部协议',
			'change': function(ev) {
				ST.only = ev.target.value;
				if (ST.only === 'all') {
					ST.proto = 'all';
					refs.proto.value = 'all';
				}
				ST.page = 1;
				loadList();
			}
		}, [
			E('option', { 'value': 'watch', 'selected': ST.only === 'watch' ? 'selected' : null }, '只看关注'),
			E('option', { 'value': 'all', 'selected': ST.only === 'all' ? 'selected' : null }, '含正常流量')
		]);
		refs.rangeLabel = E('span', { 'class': 'muted' }, '范围');
		refs.protoLabel = E('span', { 'class': 'muted' }, '协议');
		refs.onlyLabel = E('span', { 'class': 'muted' }, '视角');
		refs.count = E('span', { 'class': 'muted' }, '');

		var bar = E('div', { 'class': 'g-bar' }, [
			refs.rangeLabel, refs.range, refs.protoLabel, refs.proto, refs.onlyLabel, refs.only,
			E('span', { 'class': 'sp' }), refs.count
		]);

		refs.cols = E('colgroup', {});
		refs.thead = E('thead', {});
		// 注意：E() 只把字符串当文本节点，HTML 必须走 innerHTML，
		// 否则刷新瞬间会把 <tr><td> 源码直接显示出来。
		refs.tbody = E('tbody', {});
		refs.tbody.innerHTML = emptyRow(8, '加载中…');

		var table = E('table', { 'class': 'g-table' }, [refs.cols, refs.thead, refs.tbody]);
		var tableWrap = E('div', { 'class': 'g-tw' }, [table]);

		refs.prev = E('button', { 'click': function() { if (ST.page > 1) { ST.page--; loadList(); } } }, '上一页');
		refs.next = E('button', { 'click': function() { ST.page++; loadList(); } }, '下一页');
		refs.pageinfo = E('span', { 'class': 'pg' }, '–');

		var pager = E('div', { 'class': 'g-pager' }, [
			refs.prev, refs.pageinfo, refs.next,
			E('span', { 'class': 'sp' }),
			E('span', {}, '每页 ' + ST.size + ' 条')
		]);

		var panel = E('div', { 'class': 'g-panel' }, [refs.tabs, bar, tableWrap, pager]);

		var root = E('div', { 'class': 'guard' }, [E('style', {}, CSS), head, cards, panel]);

		// 页面高度 = 视口 − header − footer（Powered by LuCI 那句）。footer 一旦被顶出视口，
		// 整页就会长出滚动条，所以 #view 必须按实测的 header/footer 高度收缩，不能写死。
		function fitView() {
			var view = document.getElementById('view');
			if (!view || !view.contains(root)) return false;
			var hdr = document.querySelector('header');
			var ftr = document.querySelector('footer');
			var pad = 0;
			if (view.parentNode && view.parentNode !== document.body) {
				var cs = window.getComputedStyle(view.parentNode);
				pad = (parseFloat(cs.marginBottom) || 0) + (parseFloat(cs.paddingBottom) || 0);
			}
			var h = window.innerHeight
				- (hdr ? hdr.offsetHeight : 0)
				- (ftr ? ftr.offsetHeight : 0)
				- pad
				- 8;   // 页面底部留一点呼吸，否则 footer 会死死贴着面板
			view.style.height = Math.max(300, Math.round(h)) + 'px';
			return true;
		}

		function onResize() {
			if (!fitView()) window.removeEventListener('resize', onResize);
		}
		window.addEventListener('resize', onResize);

		function show(el, on) { el.style.display = on ? '' : 'none'; }

		function switchTab(t) {
			ST.tab = t; ST.page = 1;
			refs.tabs.querySelectorAll('.g-tab').forEach(function(el) {
				el.classList.toggle('on', el.getAttribute('data-tab') === t);
			});
			// 暴露面/最近连接只有 24h 明细；告警不分协议 —— 用 display 直接收掉，别留空心位
			show(refs.rangeLabel, t !== 'ports' && t !== 'events');
			show(refs.range, t !== 'ports' && t !== 'events');
			show(refs.protoLabel, t !== 'alerts');
			show(refs.proto, t !== 'alerts');
			loadList();
		}

		function renderHead() {
			var cols = COLS[ST.tab];
			refs.cols.innerHTML = cols.map(function(c) {
				return '<col style="width:' + c[1] + '%">';
			}).join('');
			refs.thead.innerHTML = '<tr>' + cols.map(function(c) {
				return '<th' + (c[2] ? ' class="num"' : '') + '>' + c[0] + '</th>';
			}).join('') + '</tr>';
		}

		function loadSummary() {
			return api('view=summary').then(function(d) {
				if (!d || d.error) throw new Error('no data');
				var s = d.stats || {};
				refs.stat.className = 'g-pill';
				refs.dot.className = 'g-dot';
				refs.status.textContent = '采集中';
				ST.wan = d.wan || '';
				refs.wan.textContent = d.wan ? 'WAN ' + d.wan : '';
				refs.uptime.textContent = '已运行 ' + Math.floor((d.uptime || 0) / 86400) + ' 天 ' +
					Math.floor((d.uptime % 86400) / 3600) + ' 小时';
				refs.updated.textContent = d.human ? '更新于 ' + d.human : '';
				var ex = fmtExposed(d.exposed);
				refs.exposed.textContent = ex.text ? '对外端口 ' + ex.text : '';
				refs.exposed.title = ex.title;

				refs['c-conn'].textContent = s.total24 != null ? s.total24 : (s.conn24 || 0);
				refs['c-conn-s'].textContent = 'TCP ' + (s.tcp24 || 0) + ' · UDP ' + (s.udp24 || 0);
				refs['c-ips'].textContent = s.src24 != null ? s.src24 : (s.ips24 || 0);
				refs['c-ips-s'].textContent = 'TCP ' + (s.srctcp || 0) + ' · UDP ' + (s.srcudp || 0);
				refs['c-watch'].textContent = s.watch24 || 0;
				refs['c-watch-s'].textContent = '公网端口命中连接';
				refs['c-alerts'].textContent = s.alerts24 || 0;
				refs['c-alerts-s'].textContent = '关注告警 · 公网/扫描';

				var cover = '明细覆盖 ' + fmtSpan(s.span_m);
				if (s.capped) cover += '（已封顶）';
				refs.cover.textContent = cover;
				refs.cover.title = s.capped
					? '连接明细达到条数上限，24 小时窗口内较早的记录已被挤出'
					: '连接明细实际覆盖时长';
			}).catch(function() {
				refs.stat.className = 'g-pill err';
				refs.dot.className = 'g-dot err';
				refs.status.textContent = '采集器未运行';
			});
		}

		function loadList() {
			renderHead();
			var qs = 'view=' + ST.tab + '&range=' + ST.range + '&page=' + ST.page +
				'&size=' + ST.size + '&proto=' + ST.proto + '&only=' + ST.only;
			return api(qs).then(function(d) {
				ST.total = d.total || 0;
				var rows = d.rows || [];
				var n = COLS[ST.tab].length;
				var empty = ST.only === 'watch'
					? '暂无需要关注的访问，切到「含正常流量」可查看正常 P2P/视频回连'
					: '暂无数据';
				refs.tbody.innerHTML = rows.length
					? rows.map(function(x) { return rowHTML(ST.tab, x); }).join('')
					: emptyRow(n, empty);
				var pages = Math.max(1, Math.ceil(ST.total / ST.size));
				var scope = [];
				scope.push(ST.tab === 'ports' || ST.tab === 'events' ? '24h'
					: ST.range === '7d' ? '7天' : ST.range === '30d' ? '30天' : '24h');
				if (ST.tab !== 'alerts' && ST.proto === 'tcp') scope.push('仅TCP');
				if (ST.only === 'watch') scope.push('关注');
				refs.count.textContent = '共 ' + ST.total + ' 条 · ' + scope.join(' · ');
				refs.pageinfo.textContent = '第 ' + ST.page + ' / ' + pages + ' 页';
				refs.prev.disabled = ST.page <= 1;
				refs.next.disabled = ST.page >= pages;
			}).catch(function() {
				refs.tbody.innerHTML = emptyRow(COLS[ST.tab].length, '读取失败');
			});
		}

		// 初始加载 + 轮询（切走页面由 poll 自动停）
		window.setTimeout(function() { fitView(); loadSummary(); loadList(); }, 0);
		poll.add(function() { return loadSummary(); }, 5);
		poll.add(function() { return loadList(); }, 15);

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
