// World tracking (SLAM) bridge for WebPlatform (client/platform/web/web_platform.gd): the 8th Wall XR
// Engine finds surfaces in the camera picture and tracks the phone in the room with six degrees of
// freedom, in Safari on iPhone too (no WebXR there). Loaded into the page with JavaScriptBridge.eval.
//
// The engine opens the back camera itself and draws it into a hidden canvas; the bridge sends Godot a
// small RGB preview of that canvas (the same 'frame' callback as alfaCamera), and Godot reads the
// camera pose and hit tests from here. Raw frames never leave the browser.
//
// The engine binary comes from cdn.jsdelivr.net on first use, unmodified: "8th Wall XR Engine"
// (c) Niantic Spatial, Inc., licensed under the XR Engine License Agreement
// (https://github.com/8thwall/engine/blob/main/LICENSE), provided "AS IS" without warranty. Used here
// in a non-commercial student project; Niantic Spatial does not endorse it.
window.alfaSlam = window.alfaSlam || (function () {
	'use strict';

	var ENGINE_URL = 'https://cdn.jsdelivr.net/npm/@8thwall/engine-binary@1.0.0/dist/xr.js';
	var LOAD_TIMEOUT_MS = 30000;
	var PREVIEW_LONG_SIDE = 160;
	var FRAME_INTERVAL_MS = 66;
	// The camera starts this high above the floor (metres): the engine's responsive scale puts the
	// floor at y = 0, so its units are about metres.
	var EYE_HEIGHT = 1.25;
	var HIT_TYPES = ['DETECTED_SURFACE', 'ESTIMATED_SURFACE', 'FEATURE_POINT'];

	var state = {
		// off | loading | initializing | limited | normal | failed | unsupported
		status: 'off', loading: null, canvas: null, preview: document.createElement('canvas'),
		callbacks: null, lastFrameAt: 0, pose: null, fov: 0, session: 0,
	};

	function report(name) {
		var callbacks = state.callbacks;
		if (!callbacks || !callbacks[name]) { return; }
		callbacks[name].apply(null, Array.prototype.slice.call(arguments, 1));
	}

	function load() {
		if (window.XR8) { return Promise.resolve(); }
		if (!state.loading) {
			state.loading = new Promise(function (resolve, reject) {
				var timer = setTimeout(function () { reject(new Error('timeout')); }, LOAD_TIMEOUT_MS);
				window.addEventListener('xrloaded', function () { clearTimeout(timer); resolve(); }, { once: true });
				var script = document.createElement('script');
				script.src = ENGINE_URL;
				script.async = true;
				script.crossOrigin = 'anonymous';
				script.setAttribute('data-preload-chunks', 'slam');
				script.onerror = function () { clearTimeout(timer); reject(new Error('load')); };
				document.head.appendChild(script);
			});
			state.loading.catch(function () { state.loading = null; });
		}
		return state.loading;
	}

	// Horizontal field of view (degrees) from the engine's column-major projection matrix.
	function fieldOfView(intrinsics) {
		return intrinsics && intrinsics[0] ? 2 * Math.atan(1 / intrinsics[0]) * 180 / Math.PI : 0;
	}

	function sendPreview() {
		var now = performance.now();
		if (now - state.lastFrameAt < FRAME_INTERVAL_MS || !state.canvas) { return; }
		state.lastFrameAt = now;
		var source = state.canvas;
		var scale = PREVIEW_LONG_SIDE / Math.max(source.width, source.height);
		var width = Math.max(1, Math.round(source.width * scale));
		var height = Math.max(1, Math.round(source.height * scale));
		var preview = state.preview;
		if (preview.width !== width || preview.height !== height) {
			preview.width = width;
			preview.height = height;
		}
		var context = preview.getContext('2d', { willReadFrequently: true });
		context.drawImage(source, 0, 0, width, height);
		var rgba = context.getImageData(0, 0, width, height).data;
		var rgb = new Uint8Array(width * height * 3);
		for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
			rgb[j] = rgba[i];
			rgb[j + 1] = rgba[i + 1];
			rgb[j + 2] = rgba[i + 2];
		}
		report('frame', width, height, rgb.buffer);
	}

	// Reads the pose of every processed frame and, right after the camera feed is drawn, the preview.
	function bridgeModule(session) {
		return {
			name: 'alfabridge',
			onCameraStatusChange: function (event) {
				if (session !== state.session) { return; }
				if (event.status === 'failed') {
					state.status = 'failed';
					report('error', 'denied');
				}
			},
			onException: function () {
				if (session !== state.session) { return; }
				state.status = 'failed';
				report('error', 'slam');
			},
			onUpdate: function (event) {
				if (session !== state.session) { return; }
				var reality = event.processCpuResult && event.processCpuResult.reality;
				if (!reality) { return; }
				state.pose = reality;
				state.fov = fieldOfView(reality.intrinsics) || state.fov;
				if (reality.trackingReason === 'INITIALIZING') {
					state.status = 'initializing';
				} else {
					state.status = reality.trackingStatus === 'NORMAL' ? 'normal' : 'limited';
				}
			},
			onRender: function () {
				if (session === state.session) { sendPreview(); }
			},
		};
	}

	// width, height: the size of the game view, so the picture and the hit tests share its shape.
	function start(width, height, callbacks) {
		stop();
		state.session += 1;
		var session = state.session;
		state.callbacks = callbacks;
		state.status = 'loading';
		load().then(function () {
			if (session !== state.session) { return; }
			var canvas = document.createElement('canvas');
			canvas.width = Math.round(width * 2);
			canvas.height = Math.round(height * 2);
			canvas.style.cssText = 'position:fixed;left:0;top:0;width:' + canvas.width + 'px;height:'
				+ canvas.height + 'px;opacity:0;pointer-events:none;z-index:-1;';
			document.body.appendChild(canvas);
			state.canvas = canvas;
			XR8.XrController.configure({ scale: 'responsive', disableWorldTracking: false });
			XR8.XrController.updateCameraProjectionMatrix({
				cam: { pixelRectWidth: canvas.width, pixelRectHeight: canvas.height, nearClipPlane: 0.01, farClipPlane: 100 },
				origin: { x: 0, y: EYE_HEIGHT, z: 0 },
				facing: { w: 1, x: 0, y: 0, z: 0 },
			});
			XR8.addCameraPipelineModules([
				XR8.GlTextureRenderer.pipelineModule(),
				XR8.XrController.pipelineModule(),
				bridgeModule(session),
			]);
			XR8.run({ canvas: canvas });
			state.status = 'initializing';
		}).catch(function () {
			if (session !== state.session) { return; }
			state.status = 'failed';
			report('error', 'library');
		});
	}

	function stop() {
		state.session += 1;
		if (window.XR8 && state.canvas) {
			try {
				XR8.stop();
				XR8.clearCameraPipelineModules();
			} catch (error) {
				// The engine was not running.
			}
		}
		if (state.canvas) { state.canvas.remove(); }
		state.canvas = null;
		state.pose = null;
		state.callbacks = null;
		if (state.status !== 'unsupported') { state.status = 'off'; }
	}

	// "px,py,pz,qx,qy,qz,qw,fov" of the camera (right-handed, y up, the camera looks along -z), or ''.
	function pose() {
		var reality = state.pose;
		if (!reality || !reality.position || !reality.rotation) { return ''; }
		var p = reality.position;
		var q = reality.rotation;
		return [p.x, p.y, p.z, q.x, q.y, q.z, q.w, state.fov].join(',');
	}

	// The surface point under (x, y), each from 0 to 1 across the game view: "x,y,z,type", or ''.
	function hitTest(x, y) {
		if (!window.XR8 || !state.canvas || state.status === 'initializing') { return ''; }
		var hits = XR8.XrController.hitTest(x, y, HIT_TYPES) || [];
		var best = null;
		hits.forEach(function (hit) {
			if (!best || HIT_TYPES.indexOf(hit.type) < HIT_TYPES.indexOf(best.type)) { best = hit; }
		});
		if (!best) { return ''; }
		return [best.position.x, best.position.y, best.position.z, best.type].join(',');
	}

	function supported() {
		return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia) && window.isSecureContext
			&& !!window.WebGLRenderingContext;
	}

	return {
		start: start,
		stop: stop,
		pose: pose,
		hitTest: hitTest,
		supported: supported,
		status: function () { return state.status; },
	};
})();
