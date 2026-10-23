// Room emblems for WebPlatform (client/platform/web/web_platform.gd): the Alfa-Bank identity (logo
// versions, the cat stickers) at the room doors in place of room QR codes. Loaded into the page with
// JavaScriptBridge.eval next to camera_bridge.js, which hands it the center of camera frames.
//
// Recognition: MediaPipe Image Embedder (MobileNet V3 small) turns a picture into a vector; a frame is
// the emblem whose reference vectors are the closest by cosine similarity. Every reference also gets
// AUGMENTED_TEMPLATES distorted copies (a wall behind, turn, skew, light, blur, noise), as a phone
// sees a printed poster. A frame counts only with a clear winner (MIN_SCORE, MIN_MARGIN over the
// second emblem), and an emblem is reported after VOTES_NEEDED of the last VOTE_WINDOW frames agree.
// The thresholds come from a test on distorted copies of the references and screenshots of the game
// as the background: no wrong emblem and no emblem on the background.
window.alfaEmblems = window.alfaEmblems || (function () {
	'use strict';

	var MODEL = 'https://storage.googleapis.com/mediapipe-models/image_embedder/mobilenet_v3_small/float32/1/mobilenet_v3_small.tflite';
	var SIDE = 224;
	var AUGMENTED_TEMPLATES = 12;
	var MIN_SCORE = 0.65;
	var MIN_MARGIN = 0.05;
	var VOTE_WINDOW = 5;
	var VOTES_NEEDED = 3;
	var REPEAT_MS = 1500;
	// Template distortions are the same on every phone.
	var TEMPLATE_SEED = 1;
	var WALLS = ['#d9d4cc', '#f2f2f2', '#9aa3ad', '#c9b79c', '#5d6670', '#e8e1d0', '#2b2f36'];

	var state = {
		// [{id, png}] from Godot: base64 PNG of each reference.
		references: [], embedder: null, templates: null, loading: null, votes: [], lastId: '', lastAt: 0,
	};

	function setReferences(json) {
		state.references = JSON.parse(json);
		state.templates = null;
		state.loading = null;
	}

	function seeded(seed) {
		var value = seed;
		return function () {
			value = (value * 16807) % 2147483647;
			return (value - 1) / 2147483646;
		};
	}

	function canvas() {
		var result = document.createElement('canvas');
		result.width = SIDE;
		result.height = SIDE;
		return result;
	}

	// The reference as printed: centred on white.
	function plain(image) {
		var result = canvas();
		var context = result.getContext('2d');
		context.fillStyle = '#fff';
		context.fillRect(0, 0, SIDE, SIDE);
		var scale = Math.min(SIDE / image.width, SIDE / image.height);
		context.drawImage(image, (SIDE - image.width * scale) / 2, (SIDE - image.height * scale) / 2,
			image.width * scale, image.height * scale);
		return result;
	}

	// The reference as a phone may see it: a poster on a wall, turned, skewed, in other light.
	function augment(image, random) {
		function between(low, high) { return low + (high - low) * random(); }
		var result = canvas();
		var context = result.getContext('2d', { willReadFrequently: true });
		var wall = context.createLinearGradient(0, 0, SIDE * random(), SIDE);
		wall.addColorStop(0, WALLS[Math.floor(random() * WALLS.length)]);
		wall.addColorStop(1, WALLS[Math.floor(random() * WALLS.length)]);
		context.fillStyle = wall;
		context.fillRect(0, 0, SIDE, SIDE);
		context.filter = 'brightness(' + between(0.65, 1.3) + ') contrast(' + between(0.7, 1.25) + ') saturate('
			+ between(0.7, 1.3) + ') blur(' + between(0, 1) + 'px)';
		var scale = between(0.55, 0.95) * SIDE / Math.max(image.width, image.height);
		var width = image.width * scale;
		var height = image.height * scale;
		context.save();
		context.translate(SIDE / 2 + between(-0.1, 0.1) * SIDE, SIDE / 2 + between(-0.1, 0.1) * SIDE);
		context.rotate(between(-0.3, 0.3));
		context.transform(1, between(-0.15, 0.15), between(-0.15, 0.15), between(0.8, 1.1), 0, 0);
		context.fillStyle = '#fff';
		context.fillRect(-width * 0.54, -height * 0.54, width * 1.08, height * 1.08);
		context.drawImage(image, -width / 2, -height / 2, width, height);
		context.restore();
		context.filter = 'none';
		var pixels = context.getImageData(0, 0, SIDE, SIDE);
		var noise = between(4, 18);
		for (var i = 0; i < pixels.data.length; i += 4) {
			var shift = (random() - 0.5) * noise;
			pixels.data[i] += shift;
			pixels.data[i + 1] += shift;
			pixels.data[i + 2] += shift;
		}
		context.putImageData(pixels, 0, 0);
		return result;
	}

	function embed(source) {
		return state.embedder.embed(source).embeddings[0].floatEmbedding;
	}

	// The vectors are L2-normalized, so the dot product is the cosine similarity.
	function similarity(a, b) {
		var sum = 0;
		for (var i = 0; i < a.length; i++) { sum += a[i] * b[i]; }
		return sum;
	}

	function loadImage(png) {
		return new Promise(function (resolve, reject) {
			var image = new Image();
			image.onload = function () { resolve(image); };
			image.onerror = function () { reject(new Error('emblem image')); };
			image.src = 'data:image/png;base64,' + png;
		});
	}

	// One emblem per macrotask: about a dozen embeddings each, so the page keeps responding.
	function buildTemplates(images) {
		var templates = [];
		var random = seeded(TEMPLATE_SEED);
		return images.reduce(function (chain, image, index) {
			return chain.then(function () {
				return new Promise(function (resolve) { setTimeout(resolve, 0); });
			}).then(function () {
				var vectors = [embed(plain(image))];
				for (var k = 0; k < AUGMENTED_TEMPLATES; k++) { vectors.push(embed(augment(image, random))); }
				templates.push({ id: state.references[index].id, vectors: vectors });
			});
		}, Promise.resolve()).then(function () { state.templates = templates; });
	}

	// mp: {module, fileset} of MediaPipe Tasks Vision from camera_bridge.js.
	function prepare(mp) {
		if (state.templates) { return Promise.resolve(); }
		if (!state.loading) {
			var references = state.references;
			var embedder = state.embedder ? Promise.resolve(state.embedder) : mp.module.ImageEmbedder.createFromOptions(mp.fileset, {
				baseOptions: { modelAssetPath: MODEL, delegate: 'CPU' }, runningMode: 'IMAGE', l2Normalize: true,
			});
			state.loading = embedder.then(function (created) {
				state.embedder = created;
				return Promise.all(references.map(function (reference) { return loadImage(reference.png); }));
			}).then(buildTemplates).catch(function (error) {
				state.loading = null;
				throw error;
			});
		}
		return state.loading;
	}

	function ready() {
		return !!(state.embedder && state.templates && state.templates.length);
	}

	function reset() {
		state.votes = [];
		state.lastId = '';
	}

	// Best emblem of one frame, '' when no emblem wins clearly.
	function classify(source) {
		var vector = embed(source);
		var bestId = '';
		var best = -1;
		var second = -1;
		state.templates.forEach(function (template) {
			var score = Math.max.apply(null, template.vectors.map(function (other) { return similarity(vector, other); }));
			if (score > best) {
				second = best;
				best = score;
				bestId = template.id;
			} else if (score > second) {
				second = score;
			}
		});
		return best >= MIN_SCORE && best - second >= MIN_MARGIN ? bestId : '';
	}

	// source: a square canvas from the center of the camera frame. Returns the emblem id once the
	// frames agree, '' otherwise; the same emblem again only after REPEAT_MS.
	function match(source, now) {
		if (!ready()) { return ''; }
		var id = classify(source);
		state.votes.push(id);
		if (state.votes.length > VOTE_WINDOW) { state.votes.shift(); }
		var votes = state.votes.filter(function (vote) { return vote === id; }).length;
		if (!id || votes < VOTES_NEEDED) { return ''; }
		if (id === state.lastId && now - state.lastAt < REPEAT_MS) { return ''; }
		state.lastId = id;
		state.lastAt = now;
		state.votes = [];
		return id;
	}

	return {
		setReferences: setReferences,
		prepare: prepare,
		ready: ready,
		reset: reset,
		match: match,
		side: SIDE,
	};
})();
