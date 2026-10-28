shader_type canvas_item;
uniform sampler2D skin_mask : filter_linear;
uniform vec4 skin_color : source_color = vec4(1.0, 0.78, 0.54, 1.0);
uniform vec4 cloth_color : source_color = vec4(0.3, 0.57, 0.91, 1.0);
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float mask = texture(skin_mask, UV).r;
	COLOR = tint * vec4(base.rgb * mix(cloth_color.rgb, skin_color.rgb, mask), base.a);
}
