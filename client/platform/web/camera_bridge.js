// Web camera, motion and speech bridge for WebPlatform (client/platform/web/web_platform.gd). Loaded
// into the page with JavaScriptBridge.eval. Frames are processed here and only results go to Godot: a
// small RGB preview, QR text, face boxes, pose landmarks, marker ids, object labels, step count,
// recognized speech. Raw camera frames never leave the browser.
//
// Libraries and models come from cdn.jsdelivr.net and storage.googleapis.com on first use (the phone
// needs internet): jsQR for QR codes; MediaPipe Tasks Vision for faces and smiles (face landmarker with
// blendshapes), the body pose (pose landmarker lite) and objects (EfficientDet-Lite0 detector with COCO
// classes plus EfficientNet-Lite0 classifier with ImageNet classes); js-aruco2 for ArUco markers.
window.alfaCamera = window.alfaCamera || (function () {
	'use strict';

	var JSQR_URL = 'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.min.js';
	var VISION_URL = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/vision_bundle.mjs';
	var VISION_WASM = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/wasm';
	var FACE_MODEL = 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';
	var POSE_MODEL = 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task';
	var DETECTOR_MODEL = 'https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/float16/1/efficientdet_lite0.tflite';
	var CLASSIFIER_MODEL = 'https://storage.googleapis.com/mediapipe-models/image_classifier/efficientnet_lite0/int8/1/efficientnet_lite0.tflite';
	// Loaded in this order: aruco.js needs CV from cv.js, the dictionary file needs AR.
	var ARUCO_URLS = [
		'https://cdn.jsdelivr.net/npm/js-aruco2@2.0.0/src/cv.js',
		'https://cdn.jsdelivr.net/npm/js-aruco2@2.0.0/src/aruco.js',
		'https://cdn.jsdelivr.net/npm/js-aruco2@2.0.0/src/dictionaries/aruco_4x4_1000.js',
	];
	// OpenCV DICT_4X4_50 (tools/printables) is the first 50 codes of DICT_4X4_1000. Its codes differ in at
	// least 4 bits, so a 1-bit error is corrected safely (the dictionary matches distances below tau).
	var MARKER_COUNT = 50;
	var MARKER_TAU = 2;
	// MediaPipe pose landmark indices for the names in SensorModels.POSE_LANDMARKS.
	var POSE_LANDMARKS = {
		nose: 0, left_shoulder: 11, right_shoulder: 12, left_hip: 23, right_hip: 24,
		left_knee: 25, right_knee: 26, left_ankle: 27, right_ankle: 28,
	};
	var PREVIEW_LONG_SIDE = 160;
	var QR_LONG_SIDE = 480;
	var FRAME_INTERVAL_MS = 66;
	var QR_INTERVAL_MS = 150;
	var FACES_INTERVAL_MS = 100;
	var POSE_INTERVAL_MS = 80;
	var MARKERS_INTERVAL_MS = 150;
	var LABELS_INTERVAL_MS = 300;
	var MARKERS_LONG_SIDE = 480;
	var MIN_LABEL_SCORE = 0.2;
	var MAX_LABELS = 6;
	var QR_REPEAT_MS = 1500;
	var MAX_FACES = 4;

	var state = {
		stream: null, video: null, mode: 'preview', front: false, timer: 0, callbacks: null,
		lastQrAt: 0, lastFacesAt: 0, lastPoseAt: 0, lastMarkersAt: 0, lastLabelsAt: 0, lastQrText: '', lastQrTextAt: 0,
		preview: document.createElement('canvas'), scan: document.createElement('canvas'),
		// Where the game wants the full-quality preview, in canvas pixels; null hides it.
		viewRect: null,
		jsQR: null, landmarker: null, pose: null, aruco: null, detector: null, classifier: null,
		loading: {}, cameraPermission: 'unknown',
	};

	function loadScript(url) {
		return new Promise(function (resolve, reject) {
			var script = document.createElement('script');
			script.src = url;
			script.onload = resolve;
			script.onerror = function () { reject(new Error('load ' + url)); };
			document.head.appendChild(script);
		});
	}

	function ensureQr() {
		if (state.jsQR) { return Promise.resolve(); }
		if (!state.loading.qr) {
			state.loading.qr = loadScript(JSQR_URL).then(function () { state.jsQR = window.jsQR; });
		}
		return state.loading.qr;
	}

	// Shared MediaPipe module and WASM fileset for every vision task.
	function vision() {
		if (!state.loading.vision) {
			state.loading.vision = import(VISION_URL).then(function (module) {
				return module.FilesetResolver.forVisionTasks(VISION_WASM).then(function (fileset) {
					return { module: module, fileset: fileset };
				});
			});
		}
		return state.loading.vision;
	}

	function ensureFaces() {
		if (state.landmarker) { return Promise.resolve(); }
		if (!state.loading.faces) {
			state.loading.faces = vision().then(function (mp) {
				return mp.module.FaceLandmarker.createFromOptions(mp.fileset, {
					baseOptions: { modelAssetPath: FACE_MODEL, delegate: 'GPU' },
					runningMode: 'VIDEO', numFaces: MAX_FACES, outputFaceBlendshapes: true,
				});
			}).then(function (landmarker) { state.landmarker = landmarker; });
		}
		return state.loading.faces;
	}

	function ensurePose() {
		if (state.pose) { return Promise.resolve(); }
		if (!state.loading.pose) {
			state.loading.pose = vision().then(function (mp) {
				return mp.module.PoseLandmarker.createFromOptions(mp.fileset, {
					baseOptions: { modelAssetPath: POSE_MODEL, delegate: 'GPU' },
					runningMode: 'VIDEO', numPoses: 1,
				});
			}).then(function (pose) { state.pose = pose; });
		}
		return state.loading.pose;
	}

	// Two models: the COCO detector knows cups, chairs, screens and bags well; the ImageNet classifier
	// adds clocks, glasses, papers and more names for the same things. Their labels are merged.
	function ensureLabels() {
		if (state.detector && state.classifier) { return Promise.resolve(); }
		if (!state.loading.labels) {
			state.loading.labels = vision().then(function (mp) {
				return Promise.all([
					mp.module.ObjectDetector.createFromOptions(mp.fileset, {
						baseOptions: { modelAssetPath: DETECTOR_MODEL, delegate: 'GPU' },
						runningMode: 'VIDEO', scoreThreshold: MIN_LABEL_SCORE, maxResults: MAX_LABELS,
					}),
					// The int8 model runs on the CPU.
					mp.module.ImageClassifier.createFromOptions(mp.fileset, {
						baseOptions: { modelAssetPath: CLASSIFIER_MODEL, delegate: 'CPU' },
						runningMode: 'VIDEO', scoreThreshold: MIN_LABEL_SCORE, maxResults: MAX_LABELS,
					}),
				]);
			}).then(function (tasks) {
				state.detector = tasks[0];
				state.classifier = tasks[1];
			});
		}
		return state.loading.labels;
	}

	function ensureMarkers() {
		if (state.aruco) { return Promise.resolve(); }
		if (!state.loading.markers) {
			state.loading.markers = ARUCO_URLS.reduce(function (chain, url) {
				return chain.then(function () { return loadScript(url); });
			}, Promise.resolve()).then(function () {
				var full = window.AR.DICTIONARIES.ARUCO_4X4_1000;
				window.AR.DICTIONARIES.ARUCO_4X4_50 = {
					nBits: full.nBits, tau: MARKER_TAU, codeList: full.codeList.slice(0, MARKER_COUNT),
				};
				state.aruco = new window.AR.Detector({ dictionaryName: 'ARUCO_4X4_50' });
			});
		}
		return state.loading.markers;
	}

	var LOADERS = { qr: ensureQr, faces: ensureFaces, pose: ensurePose, markers: ensureMarkers, labels: ensureLabels };

	function ensure(mode) {
		return LOADERS[mode] ? LOADERS[mode]() : Promise.resolve();
	}

	function report(name) {
		var args = Array.prototype.slice.call(arguments, 1);
		if (state.callbacks && state.callbacks[name]) {
			state.callbacks[name].apply(null, args);
		}
	}

	function openStream(front) {
		return navigator.mediaDevices.getUserMedia({
			audio: false,
			video: { facingMode: front ? 'user' : 'environment', width: { ideal: 1280 }, height: { ideal: 720 } },
		});
	}

	var HIDDEN_VIDEO = 'position:fixed;left:0;top:0;width:1px;height:1px;opacity:0;pointer-events:none;';

	// The game draws in a low-resolution pixel viewport, so the camera preview is the <video> element
	// itself, placed under the transparent game canvas where the game leaves a hole for it.
	function placeVideo() {
		var video = state.video;
		if (!video) { return; }
		var canvas = document.getElementById('canvas') || document.querySelector('canvas');
		var rect = state.viewRect;
		if (!rect || !canvas || !canvas.width) {
			video.style.cssText = HIDDEN_VIDEO;
			return;
		}
		var bounds = canvas.getBoundingClientRect();
		var sx = bounds.width / canvas.width;
		var sy = bounds.height / canvas.height;
		canvas.style.position = 'relative';
		canvas.style.zIndex = '1';
		canvas.style.background = 'transparent';
		video.style.cssText = 'position:fixed;z-index:0;pointer-events:none;object-fit:cover;background:#000;'
			+ 'left:' + (bounds.left + rect[0] * sx) + 'px;top:' + (bounds.top + rect[1] * sy) + 'px;'
			+ 'width:' + (rect[2] * sx) + 'px;height:' + (rect[3] * sy) + 'px;'
			+ (state.front ? 'transform:scaleX(-1);' : '');
	}

	// x, y, width, height in canvas pixels; width 0 hides the preview.
	function setView(x, y, width, height) {
		state.viewRect = width > 0 && height > 0 ? [x, y, width, height] : null;
		placeVideo();
	}

	// Draws the current video frame into `canvas` scaled to `longSide`, mirrored for the front camera.
	function grab(canvas, longSide, mirror) {
		var video = state.video;
		var scale = longSide / Math.max(video.videoWidth, video.videoHeight);
		var width = Math.max(1, Math.round(video.videoWidth * scale));
		var height = Math.max(1, Math.round(video.videoHeight * scale));
		if (canvas.width !== width || canvas.height !== height) {
			canvas.width = width;
			canvas.height = height;
		}
		var context = canvas.getContext('2d', { willReadFrequently: true });
		context.save();
		if (mirror) {
			context.translate(width, 0);
			context.scale(-1, 1);
		}
		context.drawImage(video, 0, 0, width, height);
		context.restore();
		return context.getImageData(0, 0, width, height);
	}

	function sendPreview() {
		var image = grab(state.preview, PREVIEW_LONG_SIDE, state.front);
		var rgba = image.data;
		var rgb = new Uint8Array(image.width * image.height * 3);
		for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
			rgb[j] = rgba[i];
			rgb[j + 1] = rgba[i + 1];
			rgb[j + 2] = rgba[i + 2];
		}
		report('frame', image.width, image.height, rgb.buffer);
	}

	function scanQr(now) {
		if (!state.jsQR || now - state.lastQrAt < QR_INTERVAL_MS) { return; }
		state.lastQrAt = now;
		var image = grab(state.scan, QR_LONG_SIDE, false);
		var code = state.jsQR(image.data, image.width, image.height, { inversionAttempts: 'attemptBoth' });
		if (!code || !code.data) { return; }
		if (code.data === state.lastQrText && now - state.lastQrTextAt < QR_REPEAT_MS) { return; }
		state.lastQrText = code.data;
		state.lastQrTextAt = now;
		report('qr', code.data);
	}

	function smile(blendshapes) {
		if (!blendshapes || !blendshapes.categories) { return -1; }
		var total = 0;
		var found = 0;
		blendshapes.categories.forEach(function (category) {
			if (category.categoryName === 'mouthSmileLeft' || category.categoryName === 'mouthSmileRight') {
				total += category.score;
				found += 1;
			}
		});
		return found > 0 ? Math.min(1, total / found * 1.6) : -1;
	}

	function detectFaces(now) {
		if (!state.landmarker || now - state.lastFacesAt < FACES_INTERVAL_MS) { return; }
		state.lastFacesAt = now;
		var result = state.landmarker.detectForVideo(state.video, now);
		var faces = (result.faceLandmarks || []).map(function (points, index) {
			var minX = 1, minY = 1, maxX = 0, maxY = 0;
			points.forEach(function (point) {
				minX = Math.min(minX, point.x); maxX = Math.max(maxX, point.x);
				minY = Math.min(minY, point.y); maxY = Math.max(maxY, point.y);
			});
			var x = state.front ? 1 - maxX : minX;
			return { x: x, y: minY, w: maxX - minX, h: maxY - minY, smiling: smile((result.faceBlendshapes || [])[index]) };
		});
		report('faces', JSON.stringify({ faces: faces }));
	}

	// MediaPipe may leave visibility at 0 in the browser; then a point inside the frame counts as visible.
	function likelihood(point, hasVisibility) {
		if (hasVisibility) { return point.visibility; }
		return point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1 ? 0.9 : 0.1;
	}

	// Front camera data is mirrored like the preview.
	function detectPose(now) {
		if (!state.pose || now - state.lastPoseAt < POSE_INTERVAL_MS) { return; }
		state.lastPoseAt = now;
		var points = (state.pose.detectForVideo(state.video, now).landmarks || [])[0];
		var landmarks = {};
		if (points) {
			var hasVisibility = points.some(function (point) { return point.visibility > 0; });
			Object.keys(POSE_LANDMARKS).forEach(function (name) {
				var point = points[POSE_LANDMARKS[name]];
				if (point) {
					landmarks[name] = [state.front ? 1 - point.x : point.x, point.y, likelihood(point, hasVisibility)];
				}
			});
		}
		report('pose', JSON.stringify({ landmarks: landmarks }));
	}

	function detectMarkers(now) {
		if (!state.aruco || now - state.lastMarkersAt < MARKERS_INTERVAL_MS) { return; }
		state.lastMarkersAt = now;
		var image = grab(state.scan, MARKERS_LONG_SIDE, false);
		var ids = [];
		state.aruco.detect(image).forEach(function (marker) {
			if (ids.indexOf(marker.id) < 0) { ids.push(marker.id); }
		});
		report('markers', JSON.stringify({ markers: ids }));
	}

	function detectLabels(now) {
		if (!state.detector || !state.classifier || now - state.lastLabelsAt < LABELS_INTERVAL_MS) { return; }
		state.lastLabelsAt = now;
		var best = {};
		function add(category) {
			var name = category.categoryName || category.displayName;
			if (name && !(best[name] >= category.score)) { best[name] = category.score; }
		}
		(state.detector.detectForVideo(state.video, now).detections || []).forEach(function (detection) {
			(detection.categories || []).forEach(add);
		});
		var classes = (state.classifier.classifyForVideo(state.video, now).classifications || [])[0];
		((classes && classes.categories) || []).forEach(add);
		var labels = Object.keys(best).map(function (name) {
			return { id: name, confidence: best[name] };
		}).sort(function (a, b) { return b.confidence - a.confidence; }).slice(0, MAX_LABELS);
		report('labels', JSON.stringify({ labels: labels }));
	}

	var DETECTORS = { qr: scanQr, faces: detectFaces, pose: detectPose, markers: detectMarkers, labels: detectLabels };

	function tick() {
		if (!state.video || state.video.readyState < 2) { return; }
		var now = performance.now();
		sendPreview();
		var detect = DETECTORS[state.mode];
		if (!detect) { return; }
		try {
			detect(now);
		} catch (error) {
			report('error', 'detector');
		}
	}

	function stop() {
		clearInterval(state.timer);
		state.timer = 0;
		if (state.stream) {
			state.stream.getTracks().forEach(function (track) { track.stop(); });
		}
		state.stream = null;
		if (state.video) {
			state.video.srcObject = null;
			state.video.remove();
		}
		state.video = null;
	}

	// callbacks: {frame(width, height, rgbBuffer), qr(text), faces(json), pose(json), markers(json),
	// labels(json), error(code)}.
	function start(mode, front, callbacks) {
		stop();
		state.mode = mode;
		state.front = !!front;
		state.callbacks = callbacks;
		state.lastQrText = '';
		ensure(mode).catch(function () { report('error', 'library'); });
		openStream(state.front).then(function (stream) {
			state.cameraPermission = 'granted';
			state.stream = stream;
			var video = document.createElement('video');
			// iOS plays inline video only when muted and playsinline.
			video.setAttribute('playsinline', '');
			video.muted = true;
			video.style.cssText = HIDDEN_VIDEO;
			document.body.appendChild(video);
			video.srcObject = stream;
			state.video = video;
			placeVideo();
			return video.play();
		}).then(function () {
			state.timer = setInterval(tick, FRAME_INTERVAL_MS);
		}).catch(function (error) {
			state.cameraPermission = error && error.name === 'NotAllowedError' ? 'denied' : state.cameraPermission;
			report('error', error && error.name === 'NotAllowedError' ? 'denied' : 'unavailable');
			stop();
		});
	}

	// Asks for the camera once so the permission prompt appears before a minigame starts.
	function requestPermission() {
		if (state.cameraPermission !== 'unknown' && state.cameraPermission !== 'pending') { return; }
		if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
			state.cameraPermission = 'unsupported';
			return;
		}
		state.cameraPermission = 'pending';
		openStream(false).then(function (stream) {
			stream.getTracks().forEach(function (track) { track.stop(); });
			state.cameraPermission = 'granted';
		}).catch(function (error) {
			state.cameraPermission = error && error.name === 'NotAllowedError' ? 'denied' : 'unsupported';
		});
	}

	function supported() {
		return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia) && window.isSecureContext;
	}

	return {
		start: start,
		stop: stop,
		setView: setView,
		supported: supported,
		requestPermission: requestPermission,
		permission: function () { return state.cameraPermission; },
		preload: ensure,
	};
})();

// Motion: iOS 13+ lets a page read DeviceMotionEvent only after DeviceMotionEvent.requestPermission(),
// and only from a user gesture. Godot handles input outside the DOM event, so the bridge asks on the
// first tap on the page. Steps are counted here from the acceleration magnitude.
window.alfaMotion = window.alfaMotion || (function () {
	'use strict';

	// Steps: peaks of the acceleration magnitude around its slow average (gravity). Works with the phone
	// in the hand or in a pocket; accelerationIncludingGravity is used because some phones report no
	// acceleration without gravity.
	var STEP_THRESHOLD = 0.9;
	var STEP_RESET = 0.2;
	var STEP_MIN_INTERVAL_MS = 280;
	var GRAVITY_SMOOTHING = 0.05;
	var SMOOTHING = 0.35;

	var state = {
		permission: 'unknown', steps: 0, counting: false, filtered: 0, above: false, lastStepAt: 0, slow: 9.81,
		// Last acceleration with gravity in m/s^2, Android axes: z is +9.8 with the phone flat face up.
		gravity: [0, 0, 0],
	};
	// Safari reports accelerationIncludingGravity with the opposite sign.
	var IOS = /iPad|iPhone|iPod/.test(navigator.userAgent)
		|| (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

	function needsPermission() {
		return typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function';
	}

	function askOnGesture() {
		if (!needsPermission()) {
			state.permission = typeof DeviceMotionEvent !== 'undefined' ? 'granted' : 'unsupported';
			return;
		}
		var ask = function () {
			document.removeEventListener('touchend', ask, true);
			document.removeEventListener('click', ask, true);
			DeviceMotionEvent.requestPermission().then(function (result) {
				state.permission = result === 'granted' ? 'granted' : 'denied';
			}).catch(function () { state.permission = 'denied'; });
		};
		document.addEventListener('touchend', ask, true);
		document.addEventListener('click', ask, true);
	}

	function onMotion(event) {
		var g = event.accelerationIncludingGravity;
		if (!g || g.x === null) { return; }
		var sign = IOS ? -1 : 1;
		state.gravity = [sign * g.x, sign * g.y, sign * g.z];
		if (!state.counting) { return; }
		var magnitude = Math.sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
		state.slow += GRAVITY_SMOOTHING * (magnitude - state.slow);
		state.filtered += SMOOTHING * (magnitude - state.slow - state.filtered);
		var now = performance.now();
		if (!state.above && state.filtered > STEP_THRESHOLD && now - state.lastStepAt > STEP_MIN_INTERVAL_MS) {
			state.above = true;
			state.lastStepAt = now;
			state.steps += 1;
		} else if (state.above && state.filtered < STEP_RESET) {
			state.above = false;
		}
	}

	window.addEventListener('devicemotion', onMotion);
	askOnGesture();

	return {
		permission: function () { return state.permission; },
		startSteps: function () {
			state.steps = 0;
			state.filtered = 0;
			state.above = false;
			state.slow = 9.81;
			state.counting = true;
		},
		stopSteps: function () { state.counting = false; },
		steps: function () { return state.steps; },
		acceleration: function () { return state.gravity.join(','); },
	};
})();

// Microphone: raw samples for the tuner. Godot's own microphone input does not work in the web
// export, so the samples come from getUserMedia through a ScriptProcessor and Godot drains them.
window.alfaMic = window.alfaMic || (function () {
	'use strict';

	var MAX_QUEUED = 48000;
	var state = {
		context: null, stream: null, source: null, processor: null, queue: [], queued: 0, status: 'idle', session: null,
	};

	function resumeOnGesture() {
		var resume = function () {
			document.removeEventListener('touchend', resume, true);
			document.removeEventListener('click', resume, true);
			if (state.context && state.context.state === 'suspended') { state.context.resume(); }
		};
		document.addEventListener('touchend', resume, true);
		document.addEventListener('click', resume, true);
	}

	// The audio context is created after the stream, at the microphone's own sample rate: Safari
	// resamples a microphone into a context of another rate wrongly (the voice comes out shifted by
	// about a semitone, e.g. 48 kHz microphone into a 44.1 kHz context while the game plays audio).
	function start() {
		stop();
		if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
			state.status = 'unsupported';
			return;
		}
		state.status = 'pending';
		var session = {};
		state.session = session;
		navigator.mediaDevices.getUserMedia({
			audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
			video: false,
		}).then(function (stream) {
			if (state.session !== session) {
				stream.getTracks().forEach(function (track) { track.stop(); });
				return;
			}
			var track = stream.getAudioTracks()[0];
			var settings = track && track.getSettings ? track.getSettings() : {};
			var Context = window.AudioContext || window.webkitAudioContext;
			var context;
			try {
				context = settings.sampleRate ? new Context({ sampleRate: settings.sampleRate }) : new Context();
			} catch (error) {
				context = new Context();
			}
			state.context = context;
			state.stream = stream;
			state.source = context.createMediaStreamSource(stream);
			state.processor = context.createScriptProcessor(2048, 1, 1);
			state.processor.onaudioprocess = function (event) {
				var samples = new Float32Array(event.inputBuffer.getChannelData(0));
				state.queue.push(samples);
				state.queued += samples.length;
				while (state.queued > MAX_QUEUED) { state.queued -= state.queue.shift().length; }
			};
			state.source.connect(state.processor);
			// The processor runs only while connected to the output; it writes silence.
			state.processor.connect(context.destination);
			state.status = 'granted';
			if (context.state === 'suspended') {
				context.resume();
				resumeOnGesture();
			}
		}).catch(function (error) {
			if (state.session === session) {
				state.status = error && error.name === 'NotAllowedError' ? 'denied' : 'unavailable';
			}
		});
	}

	function stop() {
		if (state.processor) { state.processor.disconnect(); state.processor.onaudioprocess = null; }
		if (state.source) { state.source.disconnect(); }
		if (state.stream) { state.stream.getTracks().forEach(function (track) { track.stop(); }); }
		if (state.context) { state.context.close(); }
		state.session = null;
		state.context = null;
		state.stream = null;
		state.source = null;
		state.processor = null;
		state.queue = [];
		state.queued = 0;
	}

	// Samples captured since the last call, at most maxFrames, as the bytes of a Float32Array.
	function take(maxFrames) {
		var count = Math.min(state.queued, maxFrames);
		var result = new Float32Array(count);
		var filled = 0;
		while (filled < count) {
			var chunk = state.queue[0];
			var part = Math.min(chunk.length, count - filled);
			result.set(chunk.subarray(0, part), filled);
			filled += part;
			if (part === chunk.length) {
				state.queue.shift();
			} else {
				state.queue[0] = chunk.subarray(part);
			}
		}
		state.queued -= count;
		return new Uint8Array(result.buffer);
	}

	return {
		start: start,
		stop: stop,
		take: take,
		status: function () { return state.status; },
		sampleRate: function () { return state.context ? state.context.sampleRate : 0; },
	};
})();

// Speech: Web Speech API (SpeechRecognition, webkitSpeechRecognition in Safari and Chrome). Chrome sends
// the audio to a cloud recognizer, Safari uses Siri dictation; both need internet. One phrase per start:
// interim results arrive while the player speaks, the last one is final.
window.alfaSpeech = window.alfaSpeech || (function () {
	'use strict';

	var Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
	var ERRORS = {
		'not-allowed': 'denied', 'service-not-allowed': 'denied', 'audio-capture': 'no-microphone',
		'no-speech': 'no-speech', 'network': 'network', 'language-not-supported': 'unsupported',
	};

	// Safari starts recognition only inside a tap, and Godot handles taps a frame later, outside the
	// DOM event. So the game arms the recognizer first (arm), the next tap on the page starts it, and
	// the start call that follows from the game within GESTURE_GRACE_MS takes it over.
	var GESTURE_GRACE_MS = 1500;

	var state = {
		recognition: null, session: null, armed: null, startedAt: 0, microphonePermission: 'unknown',
		microphoneProblem: '',
	};

	function supported() {
		return !!Recognition && window.isSecureContext;
	}

	// callbacks: {result(text, isFinal), error(code)}.
	function start(locale, callbacks) {
		if (state.recognition && state.session && performance.now() - state.startedAt < GESTURE_GRACE_MS) {
			state.session.callbacks = callbacks;
			state.session.claimed = true;
			return;
		}
		begin(locale, callbacks, true);
	}

	function begin(locale, callbacks, claimed) {
		stop();
		if (!supported()) {
			callbacks.error('unsupported');
			return;
		}
		var recognition = new Recognition();
		var session = {
			finalSent: false, lastText: '', error: '', callbacks: callbacks, claimed: claimed, locale: locale,
		};
		recognition.lang = locale;
		recognition.interimResults = true;
		recognition.continuous = false;
		recognition.maxAlternatives = 1;
		recognition.onresult = function (event) {
			if (recognition !== state.recognition) { return; }
			var text = '';
			for (var i = 0; i < event.results.length; i++) {
				text += event.results[i][0].transcript;
			}
			text = text.trim();
			var isFinal = event.results.length > 0 && event.results[event.results.length - 1].isFinal;
			session.lastText = text;
			session.finalSent = session.finalSent || isFinal;
			session.callbacks.result(text, isFinal);
		};
		recognition.onerror = function (event) { session.error = event.error || 'error'; };
		// Some browsers end without a final result: the last interim text is used instead.
		recognition.onend = function () {
			if (recognition !== state.recognition) { return; }
			state.recognition = null;
			state.session = null;
			if (!session.claimed) {
				// A tap elsewhere started it and the game never asked: wait for the next tap.
				arm(session.locale, session.callbacks);
				return;
			}
			if (session.finalSent) { return; }
			if (session.lastText) {
				session.callbacks.result(session.lastText, true);
			} else {
				session.callbacks.error(ERRORS[session.error] || session.error || 'no-speech');
			}
		};
		state.recognition = recognition;
		state.session = session;
		state.startedAt = performance.now();
		try {
			recognition.start();
		} catch (error) {
			state.recognition = null;
			state.session = null;
			callbacks.error('unavailable');
		}
	}

	function arm(locale, callbacks) {
		state.armed = supported() ? { locale: locale, callbacks: callbacks } : null;
	}

	function onGesture() {
		var armed = state.armed;
		if (!armed || state.recognition) { return; }
		state.armed = null;
		begin(armed.locale, armed.callbacks, false);
	}

	function stop() {
		state.armed = null;
		var recognition = state.recognition;
		state.recognition = null;
		state.session = null;
		if (recognition) {
			try { recognition.abort(); } catch (error) {}
		}
	}

	document.addEventListener('touchend', onGesture, true);
	document.addEventListener('mouseup', onGesture, true);

	// Asks for the microphone so the prompt appears before the minigame starts. A refusal is not
	// remembered here: the next minigame asks again, the browser itself keeps a permanent "Block".
	// After a refusal `microphoneProblem` tells why: 'site' when the page is blocked in the browser's
	// site settings, 'system' when the browser app itself has no microphone access in the phone settings
	// (the refusal comes without a prompt and the site permission is not 'denied'), plus the error name.
	function requestPermission() {
		if (state.microphonePermission === 'pending') { return; }
		if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
			state.microphonePermission = 'granted';
			return;
		}
		state.microphonePermission = 'pending';
		state.microphoneProblem = '';
		navigator.mediaDevices.getUserMedia({ audio: true, video: false }).then(function (stream) {
			stream.getTracks().forEach(function (track) { track.stop(); });
			state.microphonePermission = 'granted';
		}).catch(function (error) {
			var name = error && error.name ? error.name : 'Error';
			if (name !== 'NotAllowedError' && name !== 'SecurityError') {
				// Other errors are left to the recognizer to report.
				state.microphonePermission = 'granted';
				return;
			}
			sitePermission().then(function (site) {
				state.microphoneProblem = (site === 'denied' ? 'site' : 'system') + ':' + name;
				state.microphonePermission = 'denied';
			});
		});
	}

	function sitePermission() {
		if (!navigator.permissions || !navigator.permissions.query) { return Promise.resolve('unknown'); }
		return navigator.permissions.query({ name: 'microphone' }).then(function (status) {
			return status.state;
		}).catch(function () { return 'unknown'; });
	}

	return {
		supported: supported,
		start: start,
		arm: arm,
		stop: stop,
		requestPermission: requestPermission,
		permission: function () { return state.microphonePermission; },
		microphoneProblem: function () { return state.microphoneProblem; },
	};
})();
