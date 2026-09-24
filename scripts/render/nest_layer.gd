## 巢穴的绘制 —— 对应 JS `renderer.drawNests()`。
##
## 玩家反馈：「巢穴入口也没有，只能从地图上判断有没有到巢穴」——
## Godot 版原来**只在世界里画地形与道具，从来没画过巢穴**（只有小地图上有红点）。
##
## 这一层补上 JS 的四层画法（简化版，够看清「这里有个洞」）：
##   1. 焦土光晕（同心圆近似径向渐变）
##   2. 外翻的土堆：不规则环，形状按巢穴 id 定，每个巢各不相同但稳定
##   3. 向内塌陷的暗环（多层越来越深）
##   4. 洞口的黑 + 一颗呼吸的巢核
## 外加一个「入口」标记与铭牌：走到附近就知道按 F 能进。
class_name NestLayer extends Node2D

var world: GdWorld = null
var time := 0.0
var player_pos := Vector2.ZERO
var show_labels := true


func setup(p_world: GdWorld) -> void:
	world = p_world
	z_index = 3          # 地形之上、道具之下


func update(dt: float, p_player_pos: Vector2) -> void:
	time += dt
	player_pos = p_player_pos
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	for nest in world.nests:
		if GdMath.truthy(nest.get("destroyed", false)):
			continue
		var pos := Vector2(float(nest["x"]), float(nest["y"]))
		var r := float(nest.get("r", 64.0))
		# 视口外跳过（多画几十个洞很浪费）
		if pos.distance_to(player_pos) > 1200.0 + r:
			continue
		_draw_nest(pos, r, int(nest.get("tier", 1)), String(nest.get("id", "nest")))


func _draw_nest(pos: Vector2, r: float, tier: int, id: String) -> void:
	var seedv := float(abs(id.hash() % 1000)) * 0.01

	# ① 焦土光晕（同心圆近似）
	for i in range(6, 0, -1):
		var k := float(i) / 6.0
		draw_circle(pos, r * 2.4 * k, Color(0.7, 0.24, 0.2, 0.035))

	# ② 巢穴本体 —— 有生图贴图就用贴图（俯视虫巢），否则走程序化的土堆 + 塌陷 + 洞底
	#
	# 贴图按等级取：`nest_1..nest_5`（等级越高越"长开"），没有对应等级就退到已有档位里最近的一张。
	# 不管有没有贴图，光晕（①）、呼吸巢核、靠近提示（⑤）都保留 —— 那些是**玩法信息**，不是装饰。
	var nest_tex := _nest_tex(tier)
	if nest_tex != null:
		Sprites.draw_centered(self, nest_tex, pos, r * 2.7)
	else:
		# 外翻的土堆：不规则环
		draw_colored_polygon(_wobble_ring(pos, r * 1.34, 0.12, seedv, 0.0), Color("#4a2a22"))
		# 向内塌陷（多层越来越暗）
		draw_colored_polygon(_wobble_ring(pos, r * 1.05, 0.1, seedv, 1.3), Color("#3a2019"))
		draw_colored_polygon(_wobble_ring(pos, r * 0.78, 0.08, seedv, 2.1), Color("#2a1611"))
		# 洞底的黑
		draw_colored_polygon(_wobble_ring(pos, r * 0.52, 0.06, seedv, 3.0), Color("#120a08"))
		# 洞口边缘的抓痕（几道短线）
		for i in 4:
			var a := seedv * 6.0 + float(i) * 1.7
			var r0 := r * 1.15
			var r1 := r * 1.5
			draw_line(pos + Vector2(cos(a), sin(a)) * r0, pos + Vector2(cos(a), sin(a)) * r1,
				Color(0.55, 0.35, 0.28, 0.7), 2.0)

	# 呼吸的巢核
	var pulse := 0.5 + sin(time * 2.0 + seedv * 5.0) * 0.5
	draw_circle(pos, r * 0.2 * (0.9 + pulse * 0.15), Color(0.95, 0.35, 0.3, 0.55 + pulse * 0.3))

	# ⑤ 靠近时给入口提示（这就是玩家要的「知道到没到巢穴」）
	var d := pos.distance_to(player_pos)
	if d < 200.0:
		var t := 1.0 - d / 200.0
		draw_arc(pos, r * 1.75, 0, TAU, 40, Color(0.43, 0.9, 0.66, 0.35 + t * 0.5), 2.0)
		if show_labels:
			draw_string(ThemeDB.fallback_font, pos + Vector2(-70, -r * 1.85),
				"%d 级虫巢 —— 按 F 进入" % tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(0.85, 0.95, 0.9, 0.6 + t * 0.4))
	elif show_labels and d < 900.0:
		# 远处只给个小铭牌，避免刷屏
		draw_string(ThemeDB.fallback_font, pos + Vector2(-30, -r * 1.6),
			"%d 级虫巢" % tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.62, 0.55, 0.75))


## 巢穴贴图：按等级选档（1~6 档），找不到就退回**已有档位里最接近**的一张；
## 一张都没有就返回 null（调用方走程序化绘制）。
##
## 档位映射：10 级巢穴 → 6 张素材，用 ceil(t*0.6)（1→1、3→2、5→3、6→4、8→5、10→6），
## 让每张素材都对应一段等级，而不是前几张挤在一起。
const NEST_TIERS := 6


func _nest_tex(tier: int) -> Texture2D:
	var t := clampi(tier, 1, 10)
	var want := clampi(int(ceil(float(t) * 0.6)), 1, NEST_TIERS)
	var tex := Sprites.get_tex("nest_%d" % want)
	if tex != null:
		return tex
	for d in range(1, NEST_TIERS + 1):
		for cand in [want - d, want + d]:
			if cand >= 1 and cand <= NEST_TIERS:
				tex = Sprites.get_tex("nest_%d" % cand)
				if tex != null:
					return tex
	return null


## 不规则环（用巢穴 id 做种子，形状稳定）
func _wobble_ring(c: Vector2, rr: float, wobble: float, seedv: float, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 23:
		var a := (float(i) / 22.0) * TAU
		var w := 1.0 + sin(a * 3.0 + phase + seedv) * wobble \
			+ sin(a * 7.0 + seedv * 2.0) * wobble * 0.4
		pts.append(c + Vector2(cos(a), sin(a)) * rr * w)
	return pts
