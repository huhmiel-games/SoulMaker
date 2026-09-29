shader_type spatial;
//render_mode ambient_light_disabled; // stays OFF: the ambiance page ambient must keep lighting.
 //render_mode alpha_to_coverage, blend_mix,depth_draw_opaque,cull_back,diffuse_toon,specular_toon;

// SoulMaker base toon (P1, ADR-019): stepped diffuse ramps + rim, no outlines
// (V1). Derived from reference/shaders/flexible_toon.gdshader, which stays
// read-only. Deltas vs the original:
// - `cuts` is WIRED (was hardcoded to 2 bands); default 2 = original look.
// - `shade` WIRED as a multiplicative shadow tint (texture-derived: it
//   scales ALBEDO, never replaces it). Default black = legacy look exactly;
//   lift it to tint shadows (blue night, warm dusk).
// - normal map guarded by use_normal_map (off default: assets without normal
//   maps keep their vertex normals instead of sampling an empty texture).
// - No palette: textures ship ready-made (GIMP); the shader only does light.
uniform vec4 albedo : source_color = vec4(1.0f);
uniform vec4 shade : source_color = vec4(0.0f);
// Palette recolor (hue-shift test, character_editor groundwork): hue rotation
// in degrees + saturation/value multipliers applied to the sampled albedo.
// Defaults (0 / 1 / 1) are the identity — existing look visually unchanged
// (one HSV round-trip, float noise ~1e-7, far below the .res quantization).
// Unlike a multiply tint, hue-shift preserves painted shading detail and
// leaves near-neutrals (black soles, gray metal, white thread) ~untouched.
uniform float hue_shift_deg = 0.0f;
uniform float sat_mult = 1.0f;
uniform float val_mult = 1.0f;
// Baked look constants (validated 29/09, then frozen): shadow floor 0 =
// legacy pitch-black toon band shadows; ambient lift 0.5 keeps dark albedos
// and backlit sides readable (env ambient is ~0 and cannot do it). Tuned in
// the ColorEditor during tests, frozen here — no longer exposed per slot.
const float shadow_floor = 0.0;
const float ambient_floor = 0.5;
uniform float shadow_intensity : hint_range(0.0f, 1.0f) = 0.5f;
uniform sampler2D albedo_texture : source_color;
//uniform bool clamp_diffuse_to_max = false;

uniform int cuts : hint_range(1, 8) = 2;
uniform float wrap : hint_range(-2.0f, 2.0f) = 0.0f;
uniform float steepness : hint_range(1.0f, 8.0f) = 1.0f;

uniform bool use_attenuation = true;

uniform bool use_specular = true;
uniform float specular_strength : hint_range(0.0f, 1.0f) = 1.0f;
uniform float specular_shininess : hint_range(0.0f, 32.0f) = 16.0f;
uniform sampler2D specular_map : source_color;
// ORM mask (TEST 29/09): per-pixel metalness gates the specular dot — cloth
// (ORM blue 0) gets NO specular, metal bits (blue 1) get the full dot. Plain
// sampler, no sRGB hint: ORM is linear data, like the normal map. Dressed
// materials set use_specular from the ORM presence (source: the imported
// StandardMaterial3D.metallic_texture): no ORM = matte, never plastic.
uniform bool use_orm_mask = false;
uniform sampler2D orm_texture;
// PBR-correct metalness = factor x texture blue (the glTF default factor is
// 1 when absent). The factor alone decides matte-vs-metal: skin ships
// metallic 0 with a roughness-only map (blue filler 1) and must stay matte.
uniform float orm_metallic : hint_range(0.0f, 1.0f) = 1.0f;

uniform bool use_rim = true;
uniform vec4 rim_color : source_color = vec4(1.0f);
uniform float rim_threshold : hint_range(0.00, 1.0, 0.001) = 0.86;
uniform float rim_softness : hint_range(0.0, 1.0, 0.001) = 0.03;
uniform float rim_spread : hint_range(0.0, 1.0, 0.001) = 0.0;

uniform bool use_normal_map = false;
uniform sampler2D texture_normal : hint_normal,filter_linear_mipmap,repeat_enable;
uniform float normal_scale : hint_range(-16,16) = 1.0;

// Depth-push (anti garment poke-through, 29/09 — replaces the depth-kill
// discard, which Forward+'s depth prepass defeats: by color-pass time the
// depth buffer already holds the nearest surface, so sampling it can never
// see a buried garment). Skin writes its depth pushed back by depth_push
// meters (poke 8mm measured 29/09, push 12mm + margin): the garment's true
// depth wins wherever cloth sits within the band, in prepass AND color
// pass, regardless of draw order. Geometry untouched (no thinner bare
// skin): only depth values move. Bare skin vs background unaffected;
// skin-vs-skin keeps relative order (same push everywhere).
uniform float depth_push = 0.0;
uniform bool use_depth_push = true;

varying vec3 vertex_pos;
varying vec3 normal;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float split_specular(float specular) {
	return step(0.5f, specular);
}

void vertex() {
	vertex_pos = VERTEX;
	normal = NORMAL;
}

void fragment() {

// Depth-push (see uniforms). Godot 4.7 spatial-reference rules:
// (1) DEPTH must be written on EVERY branch — unwritten = uninitialized
// garbage on strict drivers; (2) clip space differs per renderer
// (CLIP_SPACE_FAR 0.0 Forward+/Mobile = [0,1], -1.0 Compatibility =
// [-1,1]), so the Godot-3 *0.5+0.5 mapping only fits Compatibility;
// (3) no push in the shadow pass — the push is a camera-view trick,
// light-space depths stay true. Nested ifs (no && short-circuit).
	if (IN_SHADOW_PASS) {
    	DEPTH = FRAGCOORD.z;
	} else if (use_depth_push == true) {
	    if (depth_push > 0.0) {
	        vec4 clip = PROJECTION_MATRIX * vec4(0.0, 0.0, VERTEX.z - depth_push, 1.0);
	        float ndc = clip.z / clip.w;
	        DEPTH = (CLIP_SPACE_FAR < -0.5) ? ndc * 0.5 + 0.5 : ndc;
	    } else {
        	DEPTH = FRAGCOORD.z;
    	}
	} else {
	    DEPTH = FRAGCOORD.z;
	}

	vec4 albedo_tex = texture(albedo_texture,UV);
	vec3 hsv = rgb2hsv(albedo_tex.rgb);
	hsv.x = fract(hsv.x + hue_shift_deg / 360.0);
	// Lower-clamped only: sat/val > 1 overdrive is the point (dark leathers
	// need lift + saturation to take a hue); the GPU clips the excess.
	hsv.y = max(hsv.y * sat_mult, 0.0);
	hsv.z = max(hsv.z * val_mult, 0.0);
	ALBEDO = albedo.rgb * hsv2rgb(hsv);
	if (use_normal_map) {
		NORMAL_MAP = texture(texture_normal,UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}

	ALPHA *= albedo.a * albedo_tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

void light() {
	// Attenuation.
	//float attenuation = 1.0f;
	//if (use_attenuation) {
		//attenuation = ATTENUATION;
	//}

	// ----------- toon shading
	// Godot 4: LIGHT_COLOR already carries physical energy — the legacy
	// "/ PI" (Godot 3 convention, kept from the reference shader) divided
	// all direct light by ~3.14 and made everything much too dark.
	vec3 light_color = LIGHT_COLOR;
	// Diffuse lighting.
	float NdotL = clamp(dot(NORMAL, LIGHT), 0,1);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0) + wrap;
	diffuse_amount *= steepness;
	float cuts_inv = 1.0f / float(max(cuts, 1));
	float diffuse_stepped = clamp(diffuse_amount + mod(1.0f - diffuse_amount, cuts_inv), 0.0f, 1.0f);
	vec3 diffuse = ALBEDO.rgb * ATTENUATION * light_color;
	// Shadow tint (multiplicative: the texture stays the source). shade =
	// black reproduces the legacy ramp exactly; lifting it tints shadows.
	diffuse *= diffuse_stepped + (1.0f - diffuse_stepped) * shade.rgb;
	diffuse += (ALBEDO.rgb * 0.5 + vec3(0.25)) * shadow_floor * (1.0f - diffuse_stepped);
	// Clamp diffuse to max for multiple light sources.
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * diffuse * max(dot(LIGHT,NORMAL), 0.0);
	// Per-slot ambient AFTER the clamp: it must survive on lit bands too.
	DIFFUSE_LIGHT += (ALBEDO.rgb * 0.5 + vec3(0.25)) * ambient_floor;

	// Specular lighting (TEST 29/09): Blinn-Phong QUANTIZED + gated on the
	// lit band. The smooth version veiled the whole character in plastic:
	// its 0.01-0.3 falloff tail + no shadow gate = sheen everywhere, even
	// outside the hot dot. split_specular() makes it a hard toon dot (fully
	// on/off, no veil); the gate kills it outside lit bands. Legacy tares
	// removed: no /PI (Godot 3 bug), no specular_map multiply (no asset
	// ships one). Default shininess 16 (= exp 256, small hard dot — tested
	// 29/09: 8 was a glossy veil, 16 reads as a dot). The ORM mask (above)
	// reserves specular for metal pixels; cloth is matte by construction.
	if (use_specular) {
		vec3 H = normalize(LIGHT + VIEW);
		float NdotH = clamp(dot(NORMAL, H), 0.0, 1.0);
		float specular_amount = pow(NdotH, specular_shininess * specular_shininess);
		specular_amount = split_specular(specular_amount) * step(0.5, diffuse_stepped);
		if (use_orm_mask) {
			specular_amount *= orm_metallic * texture(orm_texture, UV).b;
		}
		SPECULAR_LIGHT += specular_strength * specular_amount * light_color;
	}

	//By David Lipps aka DaveTheDev @ EXPWorlds (SoulMaker: revived 29/09)
	// Pure fresnel rim on every silhouette, lit or shadowed. The legacy form
	// never fired: the is_lit gate was only true on exact band edges and the
	// pow(NdotL) factor killed shadow-side silhouettes. Bright by design —
	// half albedo (hue hint) + half white — so it reads on dark clothes too.
	// Defaults are an EXTREME-fringe liseré (threshold 0.86, tested: 0.78
	// washes the back, 0.88 too thin elsewhere): at grazing view angles whole
	// surfaces hit fresnel ~1, so anything lower washes broad areas instead
	// of bordering them.
	if (use_rim)
	{
		float fresnel = pow(clamp(1.0 - dot(VIEW, NORMAL), 0.0, 1.0), 1.0 - rim_spread);
		float rim_value = smoothstep(rim_threshold - rim_softness, rim_threshold + rim_softness, fresnel);
		vec3 rim_tint = rim_color.rgb * (ALBEDO.rgb * 0.5 + vec3(0.5));
		DIFFUSE_LIGHT += rim_tint * rim_value * light_color;
	}
}
