// 水面波光 —— 只对偏蓝的地块生效（不需要额外分层：用颜色判断）
//
// 为什么用着色器：Canvas 版要画波光得逐格算正弦再逐个 fillRect；
// 着色器是 GPU 一次性对整屏做的，代价与地块数无关。
shader_type canvas_item;
render_mode blend_mix;

uniform float shimmer_strength : hint_range(0.0, 0.3) = 0.09;
uniform float shimmer_speed : hint_range(0.1, 3.0) = 0.9;
uniform float wave_scale : hint_range(8.0, 120.0) = 46.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// 「有多蓝」= 只在水面/酸池上叠加
	float blueness = clamp((c.b - c.r) * 5.0, 0.0, 1.0);
	float w = sin(UV.x * wave_scale + TIME * shimmer_speed)
	        * cos(UV.y * wave_scale * 0.72 - TIME * shimmer_speed * 0.8);
	float w2 = sin((UV.x + UV.y) * wave_scale * 0.5 + TIME * shimmer_speed * 1.7);
	c.rgb += blueness * (w * 0.6 + w2 * 0.4) * shimmer_strength;
	COLOR = c;
}
