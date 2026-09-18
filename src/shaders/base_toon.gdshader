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

uniform bool use_rim = true;
uniform vec4 rim_color : source_color = vec4(1.0f);
uniform float rim_threshold : hint_range(0.00, 1.0, 0.001) = 0.25;
uniform float rim_softness : hint_range(0.0, 1.0, 0.001) = 0.05;
uniform float rim_spread : hint_range(0.0, 1.0, 0.001) = 0.5;

uniform bool use_normal_map = false;
uniform sampler2D texture_normal : hint_roughness_normal,filter_linear_mipmap,repeat_enable;
uniform float normal_scale : hint_range(-16,16);

varying vec3 vertex_pos;
varying vec3 normal;

float split_specular(float specular) {
	return step(0.5f, specular);
}

void vertex() {
	vertex_pos = VERTEX;
	normal = NORMAL;
}

void fragment() {

	vec4 albedo_tex = texture(albedo_texture,UV);
	ALBEDO = albedo.rgb * albedo_tex.rgb;
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
	vec3 light_color = LIGHT_COLOR / PI;
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
	// Clamp diffuse to max for multiple light sources.
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * diffuse * max(dot(LIGHT,NORMAL), 0.0);

	// Specular lighting.
	//if (use_specular) {
		//vec3 H = normalize(LIGHT + VIEW);
		//float NdotH = dot(NORMAL, H);
		//float specular_amount = max(pow(NdotH, specular_shininess*specular_shininess), 0.0f)
							    //* texture(specular_map, UV).r
								//* ATTENUATION;
		//specular_amount = split_specular(specular_amount);
		//float light_color_desaturate = (light_color.r + light_color.g + light_color.b) / PI;
		//SPECULAR_LIGHT += specular_strength * specular_amount * light_color_desaturate;
	//}

	//By David Lipps aka DaveTheDev @ EXPWorlds
	if (use_rim)
	{
		float is_lit = step(diffuse_stepped, diffuse_amount);
		float iVdotN = 1.0 - dot(VIEW, NORMAL);
		float inverted_rim_threshold = 1.0 - rim_threshold;
		float inverted_rim_spread = 1.0 - rim_spread;

		float rim_value = iVdotN * pow(NdotL, inverted_rim_spread);
		rim_value = smoothstep(inverted_rim_threshold - rim_softness, inverted_rim_threshold + rim_softness, rim_value);
		DIFFUSE_LIGHT += rim_color.rgb * ALBEDO.rgb * rim_value * light_color * is_lit;
	}
}
