'use strict';
'require view';

return view.extend({
	render: function() {
		var frame = E('iframe', {
			'id': 'guard-frame',
			'src': '/guard/?embed=1',
			'style': 'width:100%;border:0;display:block;height:1100px;background:transparent',
			'scrolling': 'no'
		});

		window.addEventListener('message', function(ev) {
			if (ev.data && typeof ev.data.guardHeight === 'number')
				frame.style.height = (ev.data.guardHeight + 8) + 'px';
		});

		return E('div', {}, [ frame ]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
