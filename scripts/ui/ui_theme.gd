## 界面主题 —— 中文像素字体 + 科幻面板皮（素材来自 Kenney 的 UI Pack: Sci-Fi）。
##
## 为什么要在代码里建主题：
##   1. **中文字体**：Kenney 的字体只有拉丁字形，不换字体中文会退化成方块或系统字体；
##      换成 Cubic 11（OFL-1.1）后界面才像"这个游戏"的。
##   2. **面板皮**：原来面板是纯色矩形，用 UI 包的 9-slice 之后才有科幻感
##      （9-slice 的好处：一张小图能拉伸成任意尺寸而不变形）。
##
## 贴图缺失时全部退回原来的样子，不会因为少一张图就跑不起来。
class_name UiTheme

static var _cached: Theme = null


## 全局主题（缓存一份：每次调用都重建会反复读贴图）
static func get_theme() -> Theme:
	if _cached == null:
		_cached = build()
	return _cached


## 面板 9-slice 皮（生图）。贴图缺失返回 null，调用方自己退回纯色。
##
## ⚠️ 为什么不只靠主题：实测 `get_window().theme = ...` 对 **PanelContainer 的 panel 项**
## 不保证解析到（按钮能拿到、面板拿不到，同一棵树里两种结果）。
## 所以面板外壳**显式取这张皮**（ui_panels.make_window），主题那份留着给没显式设的控件。
static func panel_stylebox() -> StyleBoxTexture:
	var tex := _tex("res://assets/ui/panel_bg.png")
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	# 边距按贴图尺寸算（生图面板框的边框美术约占整图 1/6）
	var pm := maxf(6.0, roundf(tex.get_size().x / 6.0))
	sb.set_texture_margin_all(pm)
	# 内容边距跟着边框走：边框有 43px 厚，内容边距还留 14 的话文字会压在花纹上
	var cm := roundf(pm * 0.8)
	sb.content_margin_left = cm
	sb.content_margin_right = cm
	sb.content_margin_top = maxf(12.0, roundf(pm * 0.7))
	sb.content_margin_bottom = maxf(12.0, roundf(pm * 0.7))
	return sb


static func build() -> Theme:
	var th := Theme.new()
	# ① 中文像素字体（找不到就保持引擎默认）
	var font_path := "res://assets/fonts/Cubic_11.ttf"
	if ResourceLoader.exists(font_path):
		var f := load(font_path)
		if f is Font:
			th.default_font = f
			th.default_font_size = 16
	# ② 面板皮：9-slice
	var sb := panel_stylebox()
	if sb != null:
		th.set_stylebox("panel", "PanelContainer", sb)
		th.set_stylebox("panel", "Panel", sb)
		th.set_stylebox("panel", "PopupPanel", sb)
	# ③ 按钮皮：normal / hover / pressed 三态
	#
	# ⚠️ 边距按**高度**算（贴图 169×97，取 /8 ≈ 12）：按钮只有 ~35px 高，
	#    若沿用面板那种「宽度/6」的厚边距（≈28），上下两条边距加起来就超过按钮高度，
	#    9-slice 的角块会重叠 → 皮直接画不出来（实测踩过）。
	#    贴图也是照着「边框厚度约 10px」缩过的，比例才对得上。
	var btn_tex := _tex("res://assets/ui/button_bg.png")
	if btn_tex != null:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var bsb := StyleBoxTexture.new()          # ⚠️ 不能叫 sb：外层已经有同名局部变量，GDScript 报重名
			bsb.texture = btn_tex
			bsb.set_texture_margin_all(maxf(4.0, roundf(btn_tex.get_size().y / 8.0)))
			bsb.content_margin_left = 12.0
			bsb.content_margin_right = 12.0
			bsb.content_margin_top = 8.0
			bsb.content_margin_bottom = 8.0
			if state == "hover":
				bsb.modulate_color = Color(1.15, 1.18, 1.25)
			elif state == "pressed":
				bsb.modulate_color = Color(0.85, 0.92, 1.0)
			elif state == "disabled":
				bsb.modulate_color = Color(0.6, 0.62, 0.68, 0.85)
			th.set_stylebox(state, "Button", bsb)
	# ④ 文本颜色统一（深色底上用浅色字）
	th.set_color("font_color", "Label", Color("#d8e6f5"))
	th.set_color("font_color", "Button", Color("#d8e6f5"))
	th.set_color("font_color", "RichTextLabel", Color("#d8e6f5"))
	th.set_constant("separation", "VBoxContainer", 6)
	th.set_constant("separation", "HBoxContainer", 8)
	return th


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t := load(path)
		if t is Texture2D:
			return t
	return null
