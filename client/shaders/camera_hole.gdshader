shader_type canvas_item;
// Clears the pixels to transparent so the browser's full-quality camera video under the game canvas
// shows through (CameraView, PlatformServices.show_camera_view).
render_mode blend_disabled, unshaded;

void fragment() {
	COLOR = vec4(0.0);
}
