// Glowing, rounded note tiles and light beams for the falling notes.
// One quad per instance (MultiMesh). INSTANCE_CUSTOM:
//   x = width of the shape in metres, y = height in metres,
//   z = mode (0 = tile, 1 = light beam, 2 = hit burst), w = strength 0..1.
// The quad is larger than the shape by MARGIN on every side so the glow fits.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

const float MARGIN = 0.014;

varying vec4 custom;
varying vec4 tint;

void vertex() {
	custom = INSTANCE_CUSTOM;
	tint = COLOR;
}

float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 size = custom.xy;
	float mode = custom.z;
	float strength = custom.w;
	vec2 full = size + vec2(2.0 * MARGIN);
	// UV.y = 0 at the top in Godot's QuadMesh: flip so +y is up.
	vec2 p = (vec2(UV.x, 1.0 - UV.y) - 0.5) * full;
	vec3 col = tint.rgb;
	float a = 0.0;
	vec3 outc = col;

	if (mode < 0.5) {
		// Tile: rounded rectangle, bright rim, soft outer glow.
		float r = min(0.006, min(size.x, size.y) * 0.45);
		float d = sd_round_box(p, size * 0.5, r);
		float aa = fwidth(d) * 1.2 + 1e-5;
		float fill = 1.0 - smoothstep(-aa, aa, d);
		float edge = exp(-abs(d) / 0.0007);
		float glow = exp(-max(d, 0.0) / 0.0045) * (1.0 - fill);
		glow *= 1.0 - smoothstep(MARGIN * 0.55, MARGIN * 0.95, max(d, 0.0));
		// Verloop binnenin: helderder onderaan (waar de noot de toets raakt).
		float hgt = clamp((p.y + size.y * 0.5) / max(size.y, 0.001), 0.0, 1.0);
		vec3 inner = col * mix(1.05, 0.62, hgt);
		// Glanzende streep in het midden, zoals neonbuis.
		float core = exp(-pow(p.x / max(size.x * 0.22, 0.0005), 2.0));
		inner = mix(inner, mix(col, vec3(1.0), 0.45), core * 0.35 * fill);
		vec3 rimc = mix(col, vec3(1.0), 0.35);
		outc = mix(inner, rimc, clamp(edge * 0.8, 0.0, 1.0));
		outc = mix(outc, col, glow * (1.0 - fill));
		a = max(fill * 0.78, edge * 0.9);
		a = max(a, glow * 0.4);
		a *= tint.a;
	} else if (mode < 1.5) {
		// Light beam: soft vertical lane, fading upwards and to the sides.
		float x = abs(p.x) / (size.x * 0.5);
		float side = exp(-x * x * 2.2);
		float h = clamp((p.y + size.y * 0.5) / size.y, 0.0, 1.0);
		float up = pow(1.0 - h, 1.6);
		outc = mix(col, vec3(1.0), 0.15);
		a = side * up * 0.22 * strength * tint.a;
	} else {
		// Hit burst: flattened radial glow at the key.
		vec2 q = p / (size * 0.5);
		float d = length(q);
		float core = exp(-d * d * 3.0);
		outc = mix(col, vec3(1.0), 0.45 * core);
		a = core * 0.85 * strength * tint.a;
	}
	ALBEDO = outc;
	ALPHA = clamp(a, 0.0, 1.0);
}
