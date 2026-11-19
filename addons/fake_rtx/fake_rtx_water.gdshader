// Fake RTX water: puddles and pools for any Godot 4 renderer, made first for
// the GL Compatibility renderer (WebGL 2): no textures, no reflection probes.
//
// - Shape: an irregular, rounded outline cut from the quad, different for
//   every puddle (driven by world position), with a soft wet rim.
// - Surface: slow wind ripples plus drip rings that start at random spots and
//   spread out, as normals, so lamps and the torch glint off it.
// - Under the water: the floor below shows through, darkened and wet, bent
//   by the ripples (screen-space refraction).
// - Reflection: screen-space ray marching (fake ray tracing): the reflected
//   view ray is stepped through the depth buffer and, where it meets the
//   scene, that pixel of the screen is shown, faded by a Fresnel term so it
//   mirrors most at low angles, like real water.
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx, depth_draw_never;

uniform vec3 deep_colour : source_color = vec3(0.012, 0.022, 0.018);
uniform vec3 murk_colour : source_color = vec3(0.045, 0.06, 0.045);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.035;
uniform float ripple_scale = 2.6;
uniform float ripple_strength = 0.55;
uniform float drip_strength = 1.0;
uniform float drip_cell = 1.1;
uniform float reflection_strength : hint_range(0.0, 2.0) = 1.0;
uniform float refraction : hint_range(0.0, 0.1) = 0.025;
// How much of the floor's light makes it through the water and back.
uniform float clarity : hint_range(0.0, 1.0) = 0.9;
uniform float edge_noise : hint_range(0.0, 0.6) = 0.32;
uniform bool shaped = true;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float height(vec2 p, float t) {
	float h = (noise(p * ripple_scale + vec2(t * 0.30, t * 0.17)) - 0.5) * 0.55;
	h += (noise(p * ripple_scale * 2.7 - vec2(t * 0.45, -t * 0.22)) - 0.5) * 0.22;
	// Drip rings: each cell drops one now and then, at its own spot.
	vec2 cell = floor(p / drip_cell);
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 c = cell + vec2(float(i), float(j));
			float r = hash(c);
			vec2 centre = (c + vec2(hash(c + 3.1), hash(c + 7.7))) * drip_cell;
			float period = 2.5 + r * 5.0;
			float age = mod(t + r * 23.0, period);
			float d = length(p - centre);
			float front = age * 0.42;
			float band = smoothstep(0.10, 0.0, abs(d - front));
			h += sin((d - front) * 46.0) * band * exp(-age * 1.6) * 0.16 * drip_strength;
		}
	}
	return h;
}

vec2 project_uv(vec3 view_pos, mat4 projection) {
	vec4 clip = projection * vec4(view_pos, 1.0);
	return clip.xy / max(clip.w, 0.0001) * 0.5 + 0.5;
}

float scene_z(vec2 uv, mat4 inv_projection) {
	float depth = textureLod(depth_tex, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 scene = inv_projection * vec4(ndc, 1.0);
	return scene.z / scene.w;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Outline: a rounded box from the quad's UVs, frayed by world-space noise.
	float alpha = 1.0;
	if (shaped) {
		vec2 q = abs(UV * 2.0 - 1.0);
		float box = pow(pow(q.x, 4.0) + pow(q.y, 4.0), 0.25);
		float fray = (noise(world_pos.xz * 2.3) - 0.5) * edge_noise + (noise(world_pos.xz * 7.0) - 0.5) * edge_noise * 0.35;
		float inside = 0.86 - box + fray;
		if (inside < 0.0) {
			discard;
		}
		alpha = smoothstep(0.0, 0.10, inside);
	}

	float t = TIME;
	vec2 p = world_pos.xz;
	float e = 0.015;
	float hx = height(p + vec2(e, 0.0), t) - height(p - vec2(e, 0.0), t);
	float hz = height(p + vec2(0.0, e), t) - height(p - vec2(0.0, e), t);
	vec3 n_world = normalize(vec3(-hx / (2.0 * e) * ripple_strength * 0.05, 1.0, -hz / (2.0 * e) * ripple_strength * 0.05));
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	NORMAL = n_view;

	// Screen-space reflection: march the reflected ray through the depth
	// buffer, then refine the hit with a short binary search. A ray that
	// leaves the screen without a hit takes the last pixel it crossed, faded,
	// so the water never shows black holes where the reflection is unknown.
	vec3 view_dir = normalize(VERTEX);
	vec3 r = reflect(view_dir, n_view);
	vec3 reflected = vec3(0.0);
	float found = 0.0;
	vec3 ray = VERTEX + r * 0.02;
	vec3 previous = ray;
	float step_len = 0.06;
	vec2 last_uv = SCREEN_UV;
	bool hit = false;
	for (int i = 0; i < 32; i++) {
		previous = ray;
		ray += r * step_len;
		step_len *= 1.13;
		vec2 uv = project_uv(ray, PROJECTION_MATRIX);
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
		last_uv = uv;
		float behind = scene_z(uv, INV_PROJECTION_MATRIX) - ray.z;
		if (behind > 0.0 && behind < max(0.5, step_len * 2.5)) {
			hit = true;
			break;
		}
	}
	if (hit) {
		vec3 a = previous;
		vec3 b = ray;
		for (int k = 0; k < 5; k++) {
			vec3 m = (a + b) * 0.5;
			vec2 muv = project_uv(m, PROJECTION_MATRIX);
			if (scene_z(muv, INV_PROJECTION_MATRIX) - m.z > 0.0) {
				b = m;
			} else {
				a = m;
			}
		}
		last_uv = project_uv(b, PROJECTION_MATRIX);
	}
	vec2 border = min(last_uv, 1.0 - last_uv);
	float edge_fade = smoothstep(0.0, 0.1, min(border.x, border.y));
	reflected = textureLod(screen_tex, clamp(last_uv, vec2(0.001), vec2(0.999)), 0.0).rgb;
	found = (hit ? 1.0 : 0.45) * mix(0.35, 1.0, edge_fade);

	float facing = clamp(dot(-view_dir, n_view), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	float murk = noise(world_pos.xz * 1.7 + vec2(3.0, 9.0));
	vec3 water_tint = mix(deep_colour, murk_colour, murk * 0.6);

	// The floor under the water, bent by the ripples and darkened by it.
	vec2 bent = clamp(SCREEN_UV + n_view.xy * refraction, vec2(0.001), vec2(0.999));
	vec3 under = textureLod(screen_tex, bent, 0.0).rgb;
	// Wet ground is darker and a little richer in colour than dry ground.
	under = pow(under, vec3(1.06)) * clarity * (0.8 + 0.2 * normalize(water_tint + 0.001) * 1.7);

	// Missed rays see the dark room: a dim tint rather than pitch black.
	vec3 env = water_tint * 1.5 + vec3(0.012);
	vec3 mirror = mix(env, reflected, found);
	// Looking down, you mostly see through the water; at a low angle it turns
	// into a mirror (Fresnel), which is how real puddles behave.
	float mirror_amount = clamp((0.05 + fresnel * 1.5) * reflection_strength, 0.0, 1.0);
	// Bright things (lamps, lit walls) stand out in the mirror, as they do
	// in a real puddle in a dark room.
	mirror *= 1.0 + 0.8 * smoothstep(0.15, 0.6, dot(mirror, vec3(0.333)));
	// A darker wet rim where the water thins out at the edge.
	under *= mix(0.7, 1.0, alpha);

	// Lights only add glints: the colour is all in the emission.
	ALBEDO = water_tint * 0.15;
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	EMISSION = mix(under, mirror, mirror_amount);
	ALPHA = alpha;
}
