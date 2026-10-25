'use strict';
'require view';
'require poll';

var ST = { tab: 'sources', range: '24h', page: 1, size: 15, proto: 'tcp', total: 0 };

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
'.guard .g-panel{background:#fff;border:1px solid var(--line);border-radius:10px;overflow:hidden;flex:1 1 auto;min-height:0;display:flex;flex-direction:column;box-shadow:var(--sh)}',
'.guard .g-tabs{display:flex;gap:2px;padding:3px 8px;border-bottom:1px solid var(--line);flex:none}',
'.guard .g-tab{padding:3px 13px;border-radius:7px;cursor:pointer;font-size:13px;line-height:1.5;color:var(--mute);transition:background .15s,color .15s;-webkit-user-select:none;user-select:none}',
'.guard .g-tab:hover{background:#f4f6fa;color:var(--txt)}',
'.guard .g-tab.on{background:#eef1fe;color:#3f56d6;font-weight:600}',
'.guard .g-bar{display:flex;align-items:center;gap:8px;padding:0 14px;height:36px;border-bottom:1px solid var(--soft);flex:none}',
'.guard .g-bar select{height:26px;line-height:1;font-size:12.5px;padding:0 8px;border:1px solid var(--line);border-radius:6px;background:#fff;color:var(--txt);min-height:0}',
'.guard .g-bar .sp{flex:1}',
'.guard .g-bar .muted{color:var(--mute);font-size:12.5px}',
// 数据不足时下半部分不空着：用背景画「空行」分隔线，和数据行节奏对齐（从表头下方起算）
'.guard .g-tw{flex:1 1 auto;min-height:calc(8*var(--row) + var(--head));overflow:auto;background-image:linear-gradient(to bottom,var(--soft) 0 1px,transparent 1px);background-size:100% var(--row);background-position:0 var(--head);background-repeat:repeat-y}',
'.guard .g-table{width:100%;min-width:760px;margin:0;border:0;border-collapse:collapse;table-layout:fixed;background:none;box-shadow:none}',
'.guard .g-table th,.guard .g-table td{padding:0 14px;border:0;border-bottom:1px solid var(--soft);text-align:left;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;background:none}',
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
'.guard .g-table tbody tr:last-child td{border-bottom:none}',
'.guard .g-table .num{text-align:center;font-variant-numeric:tabular-nums}',
'.guard .g-num0{color:#b3bac6}',
'.guard .g-time{color:var(--mute);font-variant-numeric:tabular-nums}',
'.guard .g-ip{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12.5px;letter-spacing:-.01em}',
'.guard .g-proto{color:var(--mute);font-size:12px;letter-spacing:.03em;text-transform:uppercase}',
'.guard .g-ports{color:#5c6474;font-size:12.5px}',
'.guard .g-tag{display:inline-block;padding:0 8px;border-radius:999px;font-size:11.5px;line-height:18px;font-weight:500}',
'.guard .g-tag.scan{background:#fdecec;color:#d64545}',
'.guard .g-tag.rate{background:#fdf3e3;color:#bf7212}',
'.guard .g-ex{display:inline-block;padding:0 7px;border-radius:5px;background:#eaf1ff;color:#2f6fed;font-size:11.5px;line-height:18px;font-weight:500}',
'.guard .g-dash{color:#ccd1db}',
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
	sources: [['来源 IP', 24, 0], ['连接数', 7, 1], ['TCP', 6, 1], ['UDP', 6, 1], ['端口数', 7, 1], ['端口', 36, 0], ['最近', 14, 0]],
	alerts:  [['时间', 19, 0], ['类型', 10, 0], ['来源 IP', 26, 0], ['连接', 6, 1], ['端口', 39, 0]],
	events:  [['时间', 20, 0], ['来源 IP', 28, 0], ['目标端口', 11, 1], ['协议', 9, 0], ['对外端口', 32, 0]]
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

function rowHTML(tab, x) {
	if (tab === 'sources')
		return '<tr><td class="g-ip" title="' + esc(x.ip) + '">' + esc(x.ip) + '</td>' +
			cellNum(x.total) + cellNum(x.tcp) + cellNum(x.udp) + cellNum(x.ports) +
			'<td class="g-ports" title="' + esc(x.portlist) + '">' + esc(x.portlist) + '</td>' +
			'<td class="g-time">' + esc(x.last) + '</td></tr>';
	if (tab === 'alerts') {
		var t = x.type === 'PORT_SCAN' ? '<span class="g-tag scan">端口扫描</span>' :
			x.type === 'HIGH_RATE' ? '<span class="g-tag rate">高频连接</span>' : esc(x.type);
		return '<tr><td class="g-time">' + esc(x.t) + '</td><td>' + t + '</td>' +
			'<td class="g-ip" title="' + esc(x.ip) + '">' + esc(x.ip) + '</td>' + cellNum(x.count) +
			'<td class="g-ports" title="' + esc(x.ports) + '">' + esc(x.ports) + '</td></tr>';
	}
	return '<tr><td class="g-time">' + esc(x.t) + '</td>' +
		'<td class="g-ip" title="' + esc(x.ip) + '">' + esc(x.ip) + '</td>' + cellNum(x.dport) +
		'<td class="g-proto">' + esc(x.proto) + '</td>' +
		'<td>' + (x.exposed ? '<span class="g-ex">对外</span>' : '<span class="g-dash">—</span>') + '</td></tr>';
}

// 对外端口一长串太吵：只显示前 4 个，其余折叠成 +N
function fmtExposed(s) {
	var a = String(s || '').replace(/\s+/g, ' ').trim().split(' ').filter(Boolean);
	if (!a.length) return '';
	return a.length > 4 ? a.slice(0, 4).join(' ') + ' +' + (a.length - 4) : a.join(' ');
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

		// 标题 + 状态 + 更新时间 + 环境信息，收进一张标准白卡里
		var head = E('div', { 'class': 'g-hd' }, [
			E('div', { 'class': 'g-hd-top' }, [
				E('div', { 'class': 'g-title' }, '外部访问监控'),
				refs.stat,
				refs.updated
			]),
			E('div', { 'class': 'g-meta' }, [refs.wan, refs.uptime, refs.exposed])
		]);

		function card(k, id, color) {
			var v = E('div', { 'class': 'v' }, '–');
			refs[id] = v;
			return E('div', { 'class': 'g-card', 'style': '--ac:' + color }, [
				E('div', { 'class': 'k' }, k), v
			]);
		}

		var cards = E('div', { 'class': 'g-cards' }, [
			card('24 小时连接数', 'c-conn', '#5e72e4'),
			card('24 小时来源 IP', 'c-ips', '#11a5a0'),
			card('当前活跃外部连接', 'c-active', '#8b5cf6'),
			card('24 小时告警', 'c-alerts', '#e8833a')
		]);

		refs.tabs = E('div', { 'class': 'g-tabs' });
		[['sources', '来源 IP'], ['alerts', '告警事件'], ['events', '最近连接']].forEach(function(p) {
			refs.tabs.appendChild(E('div', {
				'class': 'g-tab' + (p[0] === ST.tab ? ' on' : ''),
				'data-tab': p[0],
				'click': function() { switchTab(p[0]); }
			}, p[1]));
		});

		refs.range = E('select', { 'change': function(ev) { ST.range = ev.target.value; ST.page = 1; loadList(); } }, [
			E('option', { 'value': '24h', 'selected': ST.range === '24h' ? 'selected' : null }, '24 小时'),
			E('option', { 'value': '7d', 'selected': ST.range === '7d' ? 'selected' : null }, '7 天'),
			E('option', { 'value': '30d', 'selected': ST.range === '30d' ? 'selected' : null }, '30 天')
		]);
		refs.proto = E('select', { 'change': function(ev) { ST.proto = ev.target.value; ST.page = 1; loadList(); } }, [
			E('option', { 'value': 'tcp', 'selected': ST.proto === 'tcp' ? 'selected' : null }, '仅 TCP'),
			E('option', { 'value': 'all', 'selected': ST.proto === 'all' ? 'selected' : null }, '全部')
		]);
		refs.rangeLabel = E('span', { 'class': 'muted' }, '时间范围');
		refs.protoLabel = E('span', { 'class': 'muted' }, '协议');
		refs.count = E('span', { 'class': 'muted' }, '');

		var bar = E('div', { 'class': 'g-bar' }, [
			refs.rangeLabel, refs.range, refs.protoLabel, refs.proto,
			E('span', { 'class': 'sp' }), refs.count
		]);

		refs.cols = E('colgroup', {});
		refs.thead = E('thead', {});
		refs.tbody = E('tbody', {}, [emptyRow(7, '加载中…')]);

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
			// 最近连接固定看 24 小时、告警不分协议 —— 用 display 直接收掉，别留空心位
			show(refs.rangeLabel, t !== 'events');
			show(refs.range, t !== 'events');
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
				refs.stat.className = 'g-pill';
				refs.dot.className = 'g-dot';
				refs.status.textContent = '采集中';
				refs.wan.textContent = d.wan ? 'WAN ' + d.wan : '';
				refs.uptime.textContent = '已运行 ' + Math.floor((d.uptime || 0) / 86400) + ' 天 ' +
					Math.floor((d.uptime % 86400) / 3600) + ' 小时';
				refs.updated.textContent = d.human ? '更新于 ' + d.human : '';
				var ex = fmtExposed(d.exposed);
				refs.exposed.textContent = ex ? '对外端口 ' + ex : '';
				refs.exposed.title = String(d.exposed || '').replace(/\s+/g, ' ').trim();
				refs['c-conn'].textContent = d.stats.conn24;
				refs['c-ips'].textContent = d.stats.ips24;
				refs['c-active'].textContent = d.stats.active;
				refs['c-alerts'].textContent = d.stats.alerts24;
			}).catch(function() {
				refs.stat.className = 'g-pill err';
				refs.dot.className = 'g-dot err';
				refs.status.textContent = '采集器未运行';
			});
		}

		function loadList() {
			renderHead();
			var qs = 'view=' + ST.tab + '&range=' + ST.range + '&page=' + ST.page +
				'&size=' + ST.size + '&proto=' + ST.proto;
			return api(qs).then(function(d) {
				ST.total = d.total || 0;
				var rows = d.rows || [];
				var n = COLS[ST.tab].length;
				refs.tbody.innerHTML = rows.length
					? rows.map(function(x) { return rowHTML(ST.tab, x); }).join('')
					: emptyRow(n, '暂无数据');
				var pages = Math.max(1, Math.ceil(ST.total / ST.size));
				refs.count.textContent = '共 ' + ST.total + ' 条';
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
