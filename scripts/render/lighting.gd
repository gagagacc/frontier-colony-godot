## 昼夜光照与光源 —— 用 Godot 的 2D 光照系统，而不是在 Canvas 里填渐变。
##
## 为什么这件事值得「发挥引擎」：
##   JS 版的 `drawLighting` 是**屏幕空间的径向渐变** —— 只能在玩家周围糊一个黑色甜甜圈，
##   光源之间不会互相影响，也照不亮地形细节。
##   Godot 有 `CanvasModulate`（全局环境色）+ `PointLight2D`（真实点光源，叠加、衰减、带纹理），
##   于是可以做到 Canvas 做不到的三件事：
##     1. **多个光源叠加**：玩家视野 + 核心舱光晕 + 枪口闪光 + 塔的照明，互不吞掉；
##     2. **光有形状**：用径向渐变纹理，边缘是柔和的，而不是硬边圆；
##     3. **环境色随时间连续变化**：黄昏整张地图偏暖，夜里偏冷蓝。
##
## 黑暗曲线**照抄 JS**（`(time % 240) / 240` 再分段），保证「几点天黑」两边一致。
class_name Lighting

var root: Node2D = null
var modulate: CanvasModulate = null
var player_light: PointLight2D = null
var base_light: PointLight2D = null
var muzzle_light: PointLight2D = null
var muzzle_timer := 0.0
var alert: TextureRect = null
var alert_time := 0.0

const DAY_LENGTH := 240.0


## 挂到场景上（`host` 一般是 Game 节点，`canvas_parent` 放光照节点）
func setup(host: Node) -> void:
	root = Node2D.new()
	root.name = "Lighting"
	host.add_child(root)

	modulate = CanvasModulate.new()
	modulate.name = "DayNight"
	root.add_child(modulate)

	var grad := _radial_gradient()
	player_light = _make_light("PlayerLight", grad, Color(1.0, 0.97, 0.9), 0.0, 1.0)
	base_light = _make_light("BaseLight", grad, Color("#5ad8ff"), 0.9, 1.6)
	muzzle_light = _make_light("MuzzleLight", grad, Color(1.0, 0.9, 0.6), 0.0, 0.35)

	# 基地挨打时的红色警戒边框（对应 JS 的 drawVignette）
	alert = TextureRect.new()
	alert.name = "AlertVignette"
	# ⚠️ 用**径向渐变**而不是纯色 ColorRect：
	#    纯色会把整屏染红（截图里一眼就看出来了），警戒边框应当只在边缘
	alert.texture = _vignette()
	alert.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	alert.stretch_mode = TextureRect.STRETCH_SCALE
	alert.modulate = Color(1, 1, 1, 0.0)
	alert.set_anchors_preset(Control.PRESET_FULL_RECT)
	alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.name = "AlertLayer"
	layer.add_child(alert)
	host.add_child(layer)


## 一圈由白到透明的径向渐变（程序化生成，不引素材）
func _radial_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


func _make_light(n: String, tex: Texture2D, col: Color, energy: float, scale: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.name = n
	l.texture = tex
	l.color = col
	l.energy = energy
	l.texture_scale = scale
	l.shadow_enabled = false
	root.add_child(l)
	return l


## 黑暗度（0 = 白天，0.55 = 夜最深）—— 与 JS `drawLighting` 的分段完全一致
static func darkness_at(time_sec: float) -> float:
	var phase := fmod(maxf(0.0, time_sec), DAY_LENGTH) / DAY_LENGTH
	if phase < 0.45:
		return 0.0
	if phase < 0.58:
		return (phase - 0.45) / 0.13 * 0.55
	if phase < 0.92:
		return 0.55
	return (1.0 - (phase - 0.92) / 0.08) * 0.55


## 环境色：把「黑暗度」换算成 CanvasModulate 的颜色。
## 夜里偏冷蓝、黄昏偏暖橙 —— 这一点 JS 做不到（它只有纯黑叠加）。
static func ambient_color(darkness: float) -> Color:
	if darkness <= 0.001:
		return Color(1, 1, 1)
	var cool := Color(0.62, 0.68, 0.92)
	var warm := Color(0.95, 0.78, 0.62)
	# 黑暗度 0.2 以下算黄昏（暖），以上算入夜（冷）
	var target := warm.lerp(cool, clampf((darkness - 0.1) / 0.3, 0.0, 1.0))
	return Color(1, 1, 1).lerp(target, clampf(darkness / 0.55, 0.0, 1.0))


## 每帧更新：环境色 + 各光源位置 + 警戒边框
func update(dt: float, time_sec: float, player_pos: Vector2, base_pos: Vector2,
	has_base: bool, base_under_attack: bool, base_destroyed: bool,
	sight_bonus: float, planet_index: int) -> void:
	if modulate == null:
		return
	var dark := darkness_at(time_sec)
	# 异星环境：非 0 号星球即使白天也压一层灰雾（对应 JS 的 envIndex 处理）
	var env_tint := Color(1, 1, 1)
	if planet_index > 0:
		env_tint = Color(0.88, 0.9, 0.86)
	modulate.color = ambient_color(dark) * env_tint

	var night := dark > 0.05
	if player_light != null:
		# 视野：白天不需要（能量 0），夜里按 sightBonus 决定半径
		var vision := (320.0 + sight_bonus * 1.4) / 256.0
		player_light.position = player_pos
		player_light.texture_scale = vision
		player_light.energy = 0.95 if night else 0.0
	if base_light != null:
		base_light.visible = has_base
		base_light.position = base_pos
		base_light.energy = (0.9 if night else 0.35) * (0.25 if base_destroyed else 1.0)
		base_light.color = Color("#ff5f6d") if base_destroyed else Color("#5ad8ff")
	if muzzle_light != null:
		if muzzle_timer > 0.0:
			muzzle_timer -= dt
			muzzle_light.energy = maxf(0.0, muzzle_timer / 0.08) * 1.2
		else:
			muzzle_light.energy = 0.0
	if alert != null:
		# 基地挨打 1.2 秒内：红色边框脉冲（JS 的 drawVignette 同义）
		if base_under_attack or base_destroyed:
			alert_time += dt
			# 夜里同样的红会显得更重，所以整体压到 60%
			var pulse := (0.16 + sin(alert_time * 6.0) * 0.07) * 0.6
			alert.modulate = Color(1, 1, 1, maxf(0.0, pulse))   # 只做柔和提示，别把整屏糊红
		else:
			alert_time = 0.0
			alert.modulate = Color(1, 1, 1, 0.0)


## 开火时闪一下（枪口光）
func muzzle_flash(pos: Vector2) -> void:
	if muzzle_light == null:
		return
	muzzle_light.position = pos
	muzzle_timer = 0.08


## 边缘红、中间透明的径向渐变
func _vignette() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.12, 0.16, 0.0))
	g.set_color(1, Color(1.0, 0.12, 0.16, 0.9))
	g.add_point(0.62, Color(1.0, 0.12, 0.16, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 144
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t