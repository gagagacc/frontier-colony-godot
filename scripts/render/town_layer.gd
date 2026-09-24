## 城镇建筑的绘制 —— **原先这些建筑在世界里根本不显示**。
##
## 查证：`town.buildings` 只在「城镇」面板里列出来（已建成 N 座），世界里没有任何地方画它，
## 而 `Sprites.structure_tex()` 定义了却没人调用 —— 玩家掏材料盖了房子，地图上什么都看不见。
##
## 照 `nest_layer.gd` 的写法做个独立图层：
##   · 有生图贴图（`struct_<type>.png`）就贴图，否则程序化画一个带屋顶的房子
##   · 屋顶颜色按建筑类型取数据表里的颜色，认得出是哪一间
##   · 血条只在受损时出现（满血不刷屏）
class_name TownLayer
extends Node2D

const LABEL_NEAR := 260.0        # 离这么近才显示建筑名

var town = null                  # Town（RefCounted）
var player: Node2D = null
var _defs: Dictionary = {}


func setup(p_town, p_player: Node2D) -> void:
	town = p_town
	player = p_player
	_defs = DataLoader.new().table("towers", "STRUCTURE_DEF", {})


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if town == null:
		return
	for b in town.buildings:
		var pos := Vector2(float(b["x"]), float(b["y"]))
		var type := String(b.get("type", ""))
		var def: Dictionary = _defs.get(type, {})
		var tint := Color(String(def.get("color", "#8a94a6")))
		var tex := Sprites.get_tex("struct_" + type)
		draw_circle(pos + Vector2(0, 12), 17.0, Color(0, 0, 0, 0.22))
		if tex != null:
			Sprites.draw_centered(self, tex, pos, 52.0)
		else:
			# 程序化：底座 + 屋顶 + 门（一眼能看出是"盖起来的房子"）
			draw_rect(Rect2(pos - Vector2(17, 14), Vector2(34, 28)), tint.darkened(0.25))
			draw_rect(Rect2(pos - Vector2(19, 18), Vector2(38, 8)), tint)
			draw_rect(Rect2(pos - Vector2(5, 2), Vector2(10, 12)), tint.darkened(0.55))
		# 受损才显示血条
		var hp := float(b.get("hp", 1.0))
		var max_hp := maxf(1.0, float(b.get("maxHp", 1.0)))
		if hp < max_hp - 0.01:
			var frac := clampf(hp / max_hp, 0.0, 1.0)
			draw_rect(Rect2(pos.x - 17.0, pos.y - 30.0, 34.0, 4.0), Color(0, 0, 0, 0.55))
			draw_rect(Rect2(pos.x - 16.0, pos.y - 29.0, 32.0 * frac, 2.0),
				Color("#6ee7a8") if frac > 0.35 else Color("#ff5f6d"))
		# 名字：只在玩家靠近时显示，避免地图上到处是字
		if player != null and pos.distance_to(player.position) < LABEL_NEAR:
			var nm := String(def.get("name", type))
			var w := ThemeDB.fallback_font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(ThemeDB.fallback_font, pos + Vector2(-w / 2.0, -24.0), nm,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#d8e6f5"))
