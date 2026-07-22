shader_type canvas_item;

// This mobile-lightweight shader is assigned only to the location TextureRect.
// Interface Controls live on another CanvasLayer and stay crisp/readable.
uniform float psyche_intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float value = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	float desaturation = psyche_intensity * 0.78;
	vec3 colour = mix(source.rgb, vec3(value), desaturation);
	colour *= 1.0 - psyche_intensity * 0.28;
	colour = mix(colour, colour * vec3(0.82, 0.90, 0.96), psyche_intensity * 0.36);

	vec2 centered = UV - vec2(0.5);
	float vignette = smoothstep(0.30, 0.76, length(centered));
	colour *= 1.0 - vignette * psyche_intensity * 0.42;

	COLOR = vec4(colour, source.a);
}
