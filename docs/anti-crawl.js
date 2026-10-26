// 搬运检测与署名提示。
// 目的不是技术封锁（web 游戏拦不住），是让顺手搬走的人至少在页面上看见署名。
(function () {
	'use strict';

	var NOTICE = '《钓肥鱼》 CC BY-NC-SA 4.0 · github.com/yes-a-hit';

	// 1. 禁右键，顺手挡掉「图片另存为」这条路。
	document.addEventListener('contextmenu', function (e) {
		e.preventDefault();
	}, { capture: true });

	// 2. 禁拖拽 canvas，防止有人把画面拖出去。
	document.addEventListener('dragstart', function (e) {
		e.preventDefault();
	}, { capture: true });

	// 3. 被别的站用 iframe 套走时，顶部挂一条来源声明。
	try {
		if (window.top !== window.self) {
			var bar = document.createElement('div');
			bar.textContent = NOTICE;
			bar.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:2147483647;' +
				'padding:6px 10px;font:12px/1.4 sans-serif;color:#fff;background:#b4552b;' +
				'text-align:center;pointer-events:none;';
			document.documentElement.appendChild(bar);
		}
	} catch (e) {
		// 跨域拿不到 window.top，说明确实被嵌了，但无法判断来源，静默。
	}

	// 4. 打开开发者工具时提示一次署名。只在窗口尺寸出现可疑变化时判定，
	//    误报就误报，反正只是弹一条提示，不拦玩。
	var warned = false;
	function checkDevtools() {
		if (warned) return;
		var gapW = window.outerWidth - window.innerWidth;
		var gapH = window.outerHeight - window.innerHeight;
		if (gapW > 180 || gapH > 180) {
			warned = true;
			console.log('%c' + NOTICE, 'font-size:14px;color:#2b6cb0;font-weight:bold');
			console.log('这个游戏的代码和素材不是公共领域。搬走请保留署名、保持同样协议、并且别拿去卖。');
		}
	}
	window.addEventListener('resize', checkDevtools);
	setInterval(checkDevtools, 2000);
}());
