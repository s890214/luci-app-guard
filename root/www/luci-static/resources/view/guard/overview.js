'use strict';
'require view';
'require poll';

var ST = { tab: 'sources', range: '24h', page: 1, size: 15, proto: 'tcp', total: 0 };

var CSS = [
'.guard{font-size:13px;color:#1f2430}',
'.guard .g-head{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin:0 0 8px}',
'.guard .g-title{font-size:17px;font-weight:600;line-height:1.4;margin:0;padding:0;background:none;border:0;box-shadow:none}',
'.guard .g-meta{display:flex;gap:10px;flex-wrap:wrap;color:#7a8194;font-size:12px}',
'.guard .g-dot{display:inline-block;width:7px;height:7px;border-radius:50%;background:#2f8f5b;margin-right:4px;vertical-align:middle}',
'.guard .g-dot.err{background:#d64545}',
'.guard .g-cards{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:8px}',
'.guard .g-card{background:#fff;border:1px solid #e6e8ec;border-radius:8px;padding:8px 12px}',
'.guard .g-card .k{color:#7a8194;font-size:12px}',
'.guard .g-card .v{font-size:19px;font-weight:600;text-align:right;font-variant-numeric:tabular-nums;line-height:1.3}',
'.guard .g-panel{background:#fff;border:1px solid #e6e8ec;border-radius:8px;overflow:hidden}',
'.guard .g-tabs{display:flex;border-bottom:1px solid #e6e8ec;background:#fafbfc}',
'.guard .g-tab{padding:8px 14px;cursor:pointer;font-size:12.5px;color:#7a8194;border-bottom:2px solid transparent}',
'.guard .g-tab.on{color:#1f2430;border-bottom-color:#5e72e4;font-weight:600;background:#fff}',
'.guard .g-bar{display:flex;align-items:center;gap:8px;padding:0 12px;border-bottom:1px solid #f0f1f4;height:38px}',
'.guard .g-bar select{height:26px;line-height:1;font-size:12px;padding:0 6px;border:1px solid #e6e8ec;border-radius:5px;background:#fff;color:#1f2430;min-height:0}',
'.guard .g-bar .sp{flex:1}',
'.guard .g-bar .muted{color:#7a8194;font-size:12px}',
'.guard .g-tw{min-height:calc(15 * 32px + 30px)}',
'.guard .g-table{width:100%;border-collapse:collapse;table-layout:fixed;background:none}',
'.guard .g-table th,.guard .g-table td{padding:6px 12px;border-bottom:1px solid #f0f1f4;text-align:left;font-size:12.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;background:none}',
'.guard .g-table th{color:#7a8194;font-weight:500;font-size:11.5px;background:#fafbfc;height:30px}',
'.guard .g-table tr:last-child td{border-bottom:none}',
'.guard .g-table .num{text-align:right;font-variant-numeric:tabular-nums}',
'.guard .g-ip{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}',
'.guard .g-tag{display:inline-block;padding:1px 7px;border-radius:999px;font-size:11px;line-height:1.7}',
'.guard .g-tag.scan{background:#fdecec;color:#d64545}',
'.guard .g-tag.rate{background:#fdf3e3;color:#c97a12}',
'.guard .g-ex{display:inline-block;padding:0 5px;border-radius:4px;background:#eaf1ff;color:#2f6fed;font-size:11px}',
'.guard .g-pager{display:flex;align-items:center;gap:8px;padding:0 12px;border-top:1px solid #f0f1f4;height:36px;color:#7a8194;font-size:12px}',
'.guard .g-pager .sp{flex:1}',
'.guard .g-pager button{height:26px;line-height:1;font-size:12px;padding:0 10px;border:1px solid #e6e8ec;border-radius:5px;background:#fff;color:#1f2430;cursor:pointer;min-height:0}',
'.guard .g-pager button:disabled{opacity:.4;cursor:default}',
'.guard .g-empty{padding:24px;text-align:center;color:#7a8194}',
'.guard .g-ports{color:#7a8194;font-size:11.5px}',
'@media(max-width:720px){.guard .g-cards{grid-template-columns:repeat(2,1fr)}}'
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
	sources: [['来源 IP', 26, 0], ['连接数', 9, 1], ['TCP', 8, 1], ['UDP', 8, 1], ['端口数', 9, 1], ['端口', 32, 0], ['最近', 8, 0]],
	alerts:  [['时间', 24, 0], ['类型', 13, 0], ['来源 IP', 27, 0], ['连接', 10, 1], ['端口', 26, 0]],
	events:  [['时间', 24, 0], ['来源 IP', 28, 0], ['目标端口', 14, 1], ['协议', 12, 0], ['对外端口', 22, 0]]
};

function rowHTML(tab, x) {
	if (tab === 'sources')
		return '<tr><td class="g-ip">' + esc(x.ip) + '</td><td class="num">' + x.total + '</td><td class="num">' + x.tcp + '</td>' +
			'<td class="num">' + x.udp + '</td><td class="num">' + x.ports + '</td>' +
			'<td class="g-ports" title="' + esc(x.portlist) + '">' + esc(x.portlist) + '</td>' +
			'<td style="color:#7a8194">' + esc(x.last) + '</td></tr>';
	if (tab === 'alerts') {
		var t = x.type === 'PORT_SCAN' ? '<span class="g-tag scan">端口扫描</span>' :
			x.type === 'HIGH_RATE' ? '<span class="g-tag rate">高频连接</span>' : esc(x.type);
		return '<tr><td style="color:#7a8194">' + esc(x.t) + '</td><td>' + t + '</td>' +
			'<td class="g-ip">' + esc(x.ip) + '</td><td class="num">' + x.count + '</td>' +
			'<td class="g-ports" title="' + esc(x.ports) + '">' + esc(x.ports) + '</td></tr>';
	}
	return '<tr><td style="color:#7a8194">' + esc(x.t) + '</td><td class="g-ip">' + esc(x.ip) + '</td>' +
		'<td class="num">' + x.dport + '</td><td style="color:#7a8194">' + esc(x.proto) + '</td>' +
		'<td>' + (x.exposed ? '<span class="g-ex">对外</span>' : '') + '</td></tr>';
}

return view.extend({
	render: function() {
		var refs = {};

		var head = E('div', { 'class': 'g-head' }, [
			E('div', { 'class': 'g-title' }, '外部访问监控'),
			refs.meta = E('div', { 'class': 'g-meta' }, [
				refs.dot = E('span', { 'class': 'g-dot' }),
				refs.status = E('span', {}, '连接中…'),
				refs.wan = E('span', {}),
				refs.uptime = E('span', {}),
				refs.updated = E('span', {}),
				refs.exposed = E('span', {})
			])
		]);

		function card(k, id) {
			var v = E('div', { 'class': 'v' }, '–');
			refs[id] = v;
			return E('div', { 'class': 'g-card' }, [E('div', { 'class': 'k' }, k), v]);
		}

		var cards = E('div', { 'class': 'g-cards' }, [
			card('24 小时连接数', 'c-conn'),
			card('24 小时来源 IP', 'c-ips'),
			card('当前活跃外部连接', 'c-active'),
			card('24 小时告警', 'c-alerts')
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
		refs.tbody = E('tbody', {}, [E('tr', {}, [E('td', { 'class': 'g-empty', 'colspan': 7 }, '加载中…')])]);

		var table = E('table', { 'class': 'g-table' }, [refs.cols, refs.thead, refs.tbody]);
		var tableWrap = E('div', { 'class': 'g-tw' }, [table]);

		refs.prev = E('button', { 'click': function() { if (ST.page > 1) { ST.page--; loadList(); } } }, '上一页');
		refs.next = E('button', { 'click': function() { ST.page++; loadList(); } }, '下一页');
		refs.pageinfo = E('span', {}, '–');

		var pager = E('div', { 'class': 'g-pager' }, [
			refs.prev, refs.pageinfo, refs.next,
			E('span', { 'class': 'sp' }),
			E('span', {}, '每页 15 条')
		]);

		var panel = E('div', { 'class': 'g-panel' }, [refs.tabs, bar, tableWrap, pager]);

		var root = E('div', { 'class': 'guard' }, [E('style', {}, CSS), head, cards, panel]);

		function switchTab(t) {
			ST.tab = t; ST.page = 1;
			refs.tabs.querySelectorAll('.g-tab').forEach(function(el) {
				el.classList.toggle('on', el.getAttribute('data-tab') === t);
			});
			refs.rangeLabel.style.visibility = (t === 'events') ? 'hidden' : 'visible';
			refs.range.style.visibility = (t === 'events') ? 'hidden' : 'visible';
			refs.protoLabel.style.visibility = (t === 'alerts') ? 'hidden' : 'visible';
			refs.proto.style.visibility = (t === 'alerts') ? 'hidden' : 'visible';
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
				refs.dot.className = 'g-dot';
				refs.status.textContent = '采集中';
				refs.wan.textContent = d.wan ? 'WAN ' + d.wan : '';
				refs.uptime.textContent = '已运行 ' + Math.floor((d.uptime || 0) / 86400) + ' 天 ' +
					Math.floor((d.uptime % 86400) / 3600) + ' 小时';
				refs.updated.textContent = '更新于 ' + (d.human || '—');
				refs.exposed.textContent = d.exposed ? '对外端口 ' + d.exposed.trim() : '';
				refs['c-conn'].textContent = d.stats.conn24;
				refs['c-ips'].textContent = d.stats.ips24;
				refs['c-active'].textContent = d.stats.active;
				refs['c-alerts'].textContent = d.stats.alerts24;
			}).catch(function() {
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
				refs.tbody.innerHTML = rows.length
					? rows.map(function(x) { return rowHTML(ST.tab, x); }).join('')
					: '<tr><td class="g-empty" colspan="' + COLS[ST.tab].length + '">暂无数据</td></tr>';
				var pages = Math.max(1, Math.ceil(ST.total / ST.size));
				refs.count.textContent = '共 ' + ST.total + ' 条';
				refs.pageinfo.textContent = '第 ' + ST.page + ' / ' + pages + ' 页';
				refs.prev.disabled = ST.page <= 1;
				refs.next.disabled = ST.page >= pages;
			}).catch(function() {
				refs.tbody.innerHTML = '<tr><td class="g-empty" colspan="' + COLS[ST.tab].length + '">读取失败</td></tr>';
			});
		}

		// 初始加载 + 轮询（切走页面由 poll 自动停）
		window.setTimeout(function() { loadSummary(); loadList(); }, 0);
		poll.add(function() { return loadSummary(); }, 5);
		poll.add(function() { return loadList(); }, 15);

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
