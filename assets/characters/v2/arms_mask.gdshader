shader_type canvas_item;
varying vec4 tint;
uniform bool female = false;
void vertex() { tint = COLOR; }
void fragment() {
	vec4 art = texture(TEXTURE, UV);
	vec2 p = UV * 512.0;
	float left = mix(181.0, 172.0, smoothstep(235.0, 278.0, p.y));
	if (female) { left = 187.0; }
	float right = mix(238.0, 242.0, smoothstep(231.0, 272.0, p.y));
	if (p.y > 204.0 && p.y < 293.0 && (p.x < left || p.x > right)) { art.a = 0.0; }
	COLOR = art * tint;
}
