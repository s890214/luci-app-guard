'use strict';
'require view';

return view.extend({
	render: function() {
		var bg = window.getComputedStyle(document.body).backgroundColor;
		if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent')
			bg = '#f4f5f7';

		var frame = E('iframe', {
			'id': 'guard-frame',
			'src': '/guard/?embed=1&bg=' + encodeURIComponent(bg),
			'style': 'width:100%;border:0;display:block;height:1000px;background:' + bg,
			'scrolling': 'no'
		});

		window.addEventListener('message', function(ev) {
			if (ev.data && typeof ev.data.guardHeight === 'number')
				frame.style.height = (ev.data.guardHeight + 2) + 'px';
		});

		return E('div', {}, [ frame ]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
