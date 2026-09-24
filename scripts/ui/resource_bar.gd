## HUD 资源条 —— **图标 + 数值**。
##
## 玩家反馈「HUD 做好」：原先资源条是一行纯文字（`金币 0  金属 0  晶体 0 …`），
## 没有图标、一行字扫读很慢，也占地方。
##
## 现在每种资源画一张小图标 + 数值；**图标缺失时自动退回文字符号**（◈▤◆ 那套），
## 所以素材可以一张一张换，不会因为少一张就开天窗。
##
## 数值为 0 的资源默认不显示（与原版 `resource_text` 的取舍一致）—— 开局只有金币时
## 不会先摆出一排 0。
class_name ResourceBar
extends Control

const ICON_PX := 18.0        # 图标边长
const ICON_GAP := 5.0        # 图标与数值之间
const GROUP_GAP := 15.0      # 两组资源之间
const ROW_H := 22.0
const FONT_PX := 14

var _values: Dictionary = {}
var _show_zero := false


func set_values(res: Dictionary) -> void:
	_values = res
	queue_redraw()


func _draw() -> void:
	var f := ThemeDB.fallback_font
	var x := 0.0
	for k in HudExtra.RESOURCE_ORDER:
		var v := int(float(_values.get(k, 0.0)))
		if v == 0 and not _show_zero:
			continue
		var tex := Sprites.get_tex("icon_" + k)
		if tex != null:
			draw_texture_rect(tex, Rect2(x, (ROW_H - ICON_PX) * 0.5, ICON_PX, ICON_PX), false)
			x += ICON_PX + ICON_GAP
		else:
			var glyph := Names.resource_icon(k)
			if glyph != "":
				draw_string(f, Vector2(x, ROW_H - 6.0), glyph,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, Color("#8fe0ff"))
				x += 16.0
		var label := str(v)
		draw_string(f, Vector2(x, ROW_H - 6.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, Color("#e8eef7"))
		x += f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x + GROUP_GAP
	# 一个资源都没有时给一句提示（与原版 resource_text 的「按 E 采集」对齐）
	if x <= 0.0:
		draw_string(f, Vector2(0, ROW_H - 6.0), "（按 E 采集）",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8ba0bb"))
