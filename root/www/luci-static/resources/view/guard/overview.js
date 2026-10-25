'use strict';
'require view';

return view.extend({
	render: function() {
		var bg = window.getComputedStyle(document.body).backgroundColor;
		if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent')
			bg = '#f4f5f7';

		// 本页没有标题，主题头部只会留一条空的紫色条 —— 直接隐藏
		var hdr = document.querySelector('header');
		if (hdr && !hdr.innerText.trim())
			hdr.style.display = 'none';

		var frame = E('iframe', {
			'id': 'guard-frame',
			'src': '/guard/?embed=1&bg=' + encodeURIComponent(bg),
			'style': 'width:100%;border:0;display:block;background:' + bg,
			'scrolling': 'no'
		});

		// 高度 = 视口 - 内容起点 - 主题页脚，保证外层不出滚动条
		function fit() {
			var vp = document.getElementById('view');
			var foot = document.querySelector('footer');
			var top = vp ? vp.getBoundingClientRect().top : 0;
			var footH = foot ? foot.getBoundingClientRect().height : 0;
			var h = window.innerHeight - top - footH - 12;
			frame.style.height = Math.max(420, Math.round(h)) + 'px';
		}

		window.addEventListener('resize', fit);
		setTimeout(fit, 0);
		setTimeout(fit, 300);

		return E('div', {}, [ frame ]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
