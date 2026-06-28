shader_type spatial;
render_mode depth_test_disabled, unshaded, blend_mix, cull_disabled;

// State transition colors
uniform vec4 color_unmatched : source_color = vec4(0.2, 0.6, 1.0, 0.4); // Icy blue
uniform vec4 color_misaligned : source_color = vec4(1.0, 0.7, 0.0, 0.6); // Amber warning
uniform vec4 color_matched : source_color = vec4(0.1, 0.9, 0.2, 0.8); // Emerald green

// Interpolation weights (controlled by GDScript tween)
uniform float weight_misaligned : hint_range(0.0, 1.0) = 0.0;
uniform float weight_matched : hint_range(0.0, 1.0) = 0.0;

// Fresnel Pulse Parameters
uniform float fresnel_power = 2.0;
uniform float pulse_speed = 3.0;
uniform float pulse_intensity = 0.5;
uniform bool enable_pulse = false;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void fragment() {
    // 1. Base color lerping based on state weights
    vec4 base_color = color_unmatched;
    base_color = mix(base_color, color_misaligned, weight_misaligned);
    base_color = mix(base_color, color_matched, weight_matched);
    
    // 2. Add flashing effect if misaligned
    if (weight_misaligned > 0.1 && weight_matched < 0.1) {
        float flash = (sin(TIME * 4.0) + 1.0) * 0.5;
        base_color.a *= mix(0.5, 1.0, flash);
    }
    
    // 3. Fresnel edge pulse when matched perfectly
    float edge_glow = 0.0;
    if (enable_pulse && weight_matched > 0.9) {
        float f = fresnel(fresnel_power, NORMAL, VIEW);
        float wave = (sin(TIME * pulse_speed) + 1.0) * 0.5;
        edge_glow = f * wave * pulse_intensity;
    }
    
    ALBEDO = base_color.rgb + vec3(edge_glow);
    ALPHA = clamp(base_color.a + edge_glow, 0.0, 1.0);
}
