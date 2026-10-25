'use strict';
'require view';

return view.extend({
	render: function() {
		window.location.replace('/guard/');
		return E('div', { 'class': 'cbi-section' }, [
			E('p', {}, '正在打开外部访问监控…')
		]);
	}
});
