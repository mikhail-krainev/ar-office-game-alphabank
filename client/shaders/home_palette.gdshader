shader_type canvas_item;
// Home palette (HomePalettes): recolours the apartment's floor and wall tiles as a gradient map. The
// brightness of each pixel picks a colour between the dark and the light colour of the palette, so
// the patterns of the tiles stay and only the colours change. Floors and walls have their own pair.
// One atlas row (the backyard grass and the house's back facade) keeps its own colours.

uniform vec4 wall_dark : source_color;
uniform vec4 wall_light : source_color;
uniform vec4 floor_dark : source_color;
uniform vec4 floor_light : source_color;
uniform float strength = 0.85;
// Atlas layout (OfficeTiles): rows are surface styles, columns 3-5 are the wall face and the cap.
uniform float atlas_rows = 16.0;
uniform float atlas_columns = 7.0;
uniform float kept_row = 15.0;

void fragment() {
	// In Godot 4 COLOR already holds the texture colour times the modulate.
	vec4 base = COLOR;
	float row = floor(UV.y * atlas_rows);
	float column = floor(UV.x * atlas_columns);
	if (abs(row - kept_row) > 0.5) {
		float brightness = dot(base.rgb, vec3(0.299, 0.587, 0.114));
		bool is_wall = column > 2.5 && column < 5.5;
		vec3 dark = is_wall ? wall_dark.rgb : floor_dark.rgb;
		vec3 light = is_wall ? wall_light.rgb : floor_light.rgb;
		vec3 mapped = mix(dark, light, smoothstep(0.12, 0.95, brightness));
		base.rgb = mix(base.rgb, mapped, strength);
	}
	COLOR = base;
}
