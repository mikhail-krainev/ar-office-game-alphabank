shader_type canvas_item;
// Full-screen retro post-process: curvature, chromatic aberration, cheap glow, scanlines, noise, vignette.
// Transparent pixels stay transparent: the web camera video under the canvas shows through them.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float curvature : hint_range(0.0, 0.2) = 0.02;
uniform float aberration_px : hint_range(0.0, 3.0) = 0.5;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.25;
uniform float glow_threshold : hint_range(0.0, 1.0) = 0.85;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.06;
uniform float noise_strength : hint_range(0.0, 0.3) = 0.018;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 bend(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	centered *= 1.0 + curvature * dot(centered.yx, centered.yx);
	return centered * 0.5 + 0.5;
}

vec3 sample_bright(vec2 uv) {
	vec3 color = texture(screen_texture, uv).rgb;
	return max(color - glow_threshold, vec3(0.0));
}

void fragment() {
	vec2 uv = bend(SCREEN_UV);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec2 px = SCREEN_PIXEL_SIZE;
		float alpha = texture(screen_texture, SCREEN_UV).a;
		vec3 color;
		color.r = texture(screen_texture, uv + vec2(px.x * aberration_px, 0.0)).r;
		color.g = texture(screen_texture, uv).g;
		color.b = texture(screen_texture, uv - vec2(px.x * aberration_px, 0.0)).b;

		vec3 glow = vec3(0.0);
		glow += sample_bright(uv + vec2(2.0, 0.0) * px);
		glow += sample_bright(uv - vec2(2.0, 0.0) * px);
		glow += sample_bright(uv + vec2(0.0, 2.0) * px);
		glow += sample_bright(uv - vec2(0.0, 2.0) * px);
		glow += sample_bright(uv + vec2(3.0, 3.0) * px);
		glow += sample_bright(uv - vec2(3.0, 3.0) * px);
		glow += sample_bright(uv + vec2(3.0, -3.0) * px);
		glow += sample_bright(uv - vec2(3.0, -3.0) * px);
		color += glow / 8.0 * glow_strength;

		float row = floor(uv.y / px.y);
		color *= 1.0 - scanline_strength * mod(row, 2.0);

		color += (hash(uv * 512.0 + fract(TIME) * 97.0) - 0.5) * noise_strength;

		vec2 centered = uv * 2.0 - 1.0;
		color *= clamp(1.0 - vignette_strength * 0.35 * dot(centered, centered), 0.0, 1.0);

		COLOR = vec4(color, alpha);
	}
}
