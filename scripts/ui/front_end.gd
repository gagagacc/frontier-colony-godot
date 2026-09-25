## 开场与二级界面 —— 标题 / 模式 / 角色 / 星球 / 设置 / 生成中。
##
## 为什么重写：原来只有一个「盖在游戏上面的窗口」——
## 世界已经生成、虫群已经在打基地，玩家还在选角色。那不是开场界面，那是一层遮罩。
## 现在的规矩：
##   1. **前置流程走完之前，世界不生成、模拟不推进**（`Game.playing = false`）；
##   2. 每一屏都是**整屏**的（带不透明底），背后不会漏出战场；
##   3. 选完星球与种子才开始生成，生成时显示「生成中」而不是卡住；
##   4. 游戏内 Esc 的暂停面板另有一套（见 game.gd），两者互不干扰。
##
## 对外只有三个回调：`on_start(params)` / `on_quit()` / `on_open_settings()`。
class_name FrontEnd

enum Screen { TITLE, MODE, CHARACTER, PLANET, LOADING, SETTINGS, LANDING }

signal start_requested(params: Dictionary)
## 选好降落点后发出（带选中的 site 字典）
signal landing_confirmed(site: Dictionary)
signal quit_requested

var screen: int = Screen.TITLE
var mode := "frontier"
var character := "engineer"
var seed_text := ""
var planet_index := 0
var root: Control = null
var _loading_msg := "正在生成世界…"
var _loading_detail := ""
## 选降落点用：世界已经生成好了，这里只是拿它的 landing_sites
var landing_world: GdWorld = null
var landing_map: LandingMap = null


func _init() -> void:
	seed_text = random_seed_text()


static func random_seed_text() -> String:
	return "frontier-" + str(randi() % 9000 + 1000)


# =========================================================
#  界面
# =========================================================

## 挂到 `$UI` 上（CanvasLayer 也行）
func attach(host: Node) -> void:
	detach()
	root = Control.new()
	root.name = "FrontEnd"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(root)
	rebuild()


func detach() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null


func goto(s: int) -> void:
	screen = s
	rebuild()


## 每一屏的专属背景贴图（`assets/sprites/ui_bg_<name>.png`）；没有就返回 null（退回纯色）
func _screen_bg_texture(s: int) -> Texture2D:
	var name := ""
	match s:
		Screen.TITLE:
			name = "title"
		Screen.PLANET:
			name = "planet"
		Screen.CHARACTER:
			name = "character"
		Screen.SETTINGS:
			name = "settings"
		_:
			return null
	return Sprites.get_tex("ui_bg_" + name)


func rebuild() -> void:
	if root == null:
		return
	# ⚠️ 必须先 remove_child 再 queue_free：queue_free 是**延迟**的，
	# 只调它的话旧界面会留在树里整整一帧 —— 表现是「新界面和旧界面叠在一起」，
	# 而且点击可能命中已经被替换掉的旧按钮（流程测试就是这么抓到它的）。
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()
	# 全屏底：优先用**这一屏专属的生图背景**（ui_bg_<screen>.png），
	# 没有就退回纯色。背景之上再压一层半透明暗色，保证文字始终读得清。
	var bg_tex := _screen_bg_texture(screen)
	if bg_tex != null:
		var tr := TextureRect.new()
		tr.texture = bg_tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		root.add_child(tr)
		var veil := ColorRect.new()
		veil.color = Color(0.03, 0.05, 0.09, 0.55)
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(veil)
	else:
		var bg := ColorRect.new()
		bg.color = Color("#0b0f16")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(120, 70)
	box.custom_minimum_size = Vector2(1040, 0)
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	match screen:
		Screen.TITLE:
			_build_title(box)
		Screen.MODE:
			_build_mode(box)
		Screen.CHARACTER:
			_build_character(box)
		Screen.PLANET:
			_build_planet(box)
		Screen.LOADING:
			_build_loading(box)
		Screen.SETTINGS:
			_build_settings(box)
		Screen.LANDING:
			_build_landing(box)


func _title(text: String, size: int = 34) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _sub(text: String, width: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("#8ba0bb"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# ⚠️ 不要在子标签上写死很大的 min width：它会把整行撑出屏幕，
	# 表现是「文字被右边缘切掉」（模式/角色那两屏就是这么出问题的）。
	# 需要限宽时由调用方传 width，由**父容器**决定换行宽度。
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0)
	return l


func _btn(text: String, cb: Callable, size := Vector2(260, 38)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.pressed.connect(cb)
	return b


## 一排按钮
func _row(buttons: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for b in buttons:
		h.add_child(b)
	return h


func _spacer(h: int = 12) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


# ---------- 标题 ----------
func _build_title(box: Node) -> void:
	box.add_child(_title("开拓者：殖民地", 52))
	box.add_child(_sub("2D 外星殖民 —— 塔防 + 开放世界 + 城镇经营 · Godot 4.4 移植版"))
	box.add_child(_spacer(28))
	box.add_child(_row([
		_btn("开始游戏", func() -> void: goto(Screen.MODE)),
		_btn("设置", func() -> void: goto(Screen.SETTINGS)),
		_btn("退出", func() -> void: quit_requested.emit()),
	]))
	box.add_child(_spacer(10))
	var has_save := FileAccess.file_exists("user://saves/slot1.json")
	var cont := _btn("继续上次存档（slot1）", func() -> void: _continue_save())
	cont.disabled = not has_save
	box.add_child(_row([cont,
		_btn("重置存档槽位", func() -> void: _wipe_saves(), Vector2(200, 38))]))
	box.add_child(_spacer(24))
	box.add_child(_sub("流程：标题 → 模式 → 角色 → 星球与种子 → 生成世界 → 落地。\n" +
		"前三屏都不会开始模拟 —— 虫群要等你落地之后才动。"))


func _continue_save() -> void:
	var data := SaveGame.load_data("slot1")
	if data.is_empty():
		return
	mode = String(data.get("mode", "frontier"))
	character = String(data.get("characterId", "engineer"))
	seed_text = String(data.get("seed", seed_text))
	planet_index = int(data.get("planetIndex", 0))
	var params := start_params()
	params["load_slot"] = "slot1"
	start_requested.emit(params)


func _wipe_saves() -> void:
	for slot in SaveGame.list_slots():
		var path := SaveGame.slot_path(String(slot))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	rebuild()


# ---------- 选择项的通用画法 ----------
#
# 之前的做法是「点一下 = 选中 + 立刻跳下一屏」，而且**当前那项是禁用的（灰的）**——
# 玩家的原话：「我选中了怎么确定呢，我要怎么选中进入游戏呢」。
# 这不是文案问题，是流程问题：**选中要看得见，确定要有个明确的按钮**。
#
# 现在的规矩：
#   1. 点选项 = 只选中（不跳屏），选中项高亮 + 打勾 + 描边；
#   2. 每屏底部固定一行：`← 返回` + `下一步 →`（最后一屏是 `开始游戏 →`）；
#   3. 回车/空格也能触发那一行（把焦点给它）。

const SELECTED_COLORS := {
	"mode": Color("#6ee7a8"), "character": Color("#8fe0ff"), "planet": Color("#ffba4c"),
}


func _option_button(text: String, selected: bool, tint: Color, cb: Callable,
	size: Vector2) -> Button:
	var b := Button.new()
	b.text = ("✓ " if selected else "  ") + text
	b.custom_minimum_size = size
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if selected:
		b.add_theme_color_override("font_color", tint)
		b.add_theme_color_override("font_hover_color", tint)
		b.add_theme_color_override("font_pressed_color", tint)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(tint.r, tint.g, tint.b, 0.16)
		sb.border_color = tint
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
	else:
		b.add_theme_color_override("font_color", Color("#c9d4e0"))
	b.pressed.connect(cb)
	return b


## 每屏底部：返回 + 下一步/开始（返回 nil 表示不显示返回）
func _footer(box: Node, back_to: Variant, next_text: String, next_cb: Callable,
	next_enabled: bool = true) -> void:
	box.add_child(_spacer(18))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if back_to != null:
		row.add_child(_btn("← 返回", func() -> void: goto(int(back_to)), Vector2(150, 44)))
	var next := _btn(next_text, next_cb, Vector2(240, 44))
	next.disabled = not next_enabled
	# 焦点默认落在「下一步」：回车/空格就能确定
	next.grab_focus()
	row.add_child(next)
	box.add_child(row)


# ---------- 模式 ----------
func _build_mode(box: Node) -> void:
	box.add_child(_title("选择模式", 32))
	box.add_child(_sub("点一下选中（会打勾），然后在下面点「下一步」。两种模式的差别全在数据里：有没有角色、撒不撒巢穴、怪潮从哪来、能建多远。"))
	box.add_child(_spacer(16))
	var mods := DataLoader.new().module("modes")
	var defs: Dictionary = mods.get("MODE_DEF", {})
	for id in mods.get("MODE_LIST", []):
		var d: Dictionary = defs.get(String(id), {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var sel := String(id) == mode
		var id_c := String(id)
		var pick := _option_button("%s %s" % [String(d.get("icon", "")), String(d.get("name", id))],
			sel, Color("#6ee7a8"), func() -> void:
				mode = id_c
				rebuild(), Vector2(260, 60))
		row.add_child(pick)
		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(820, 0)
		var tag := Label.new()
		tag.text = String(d.get("tagline", ""))
		tag.add_theme_color_override("font_color", Color("#ffba4c") if sel else Color("#8ba0bb"))
		info.add_child(tag)
		var desc := _sub(String(d.get("desc", "")), 820.0)
		info.add_child(desc)
		for b in d.get("bullets", []):
			info.add_child(_sub("  · " + String(b), 820.0))
		row.add_child(info)
		box.add_child(row)
		box.add_child(_spacer(10))
	_footer(box, Screen.TITLE, "下一步：选角色 →", func() -> void: goto(Screen.CHARACTER))


# ---------- 角色 ----------
func _build_character(box: Node) -> void:
	box.add_child(_title("选择角色", 32))
	box.add_child(_sub("点一下选中（会打勾），然后点「下一步」。角色决定基础属性与被动 —— 被动里的数值会直接进属性引擎（修塔折扣、油耗、撞击、基因位…）。"))
	box.add_child(_spacer(14))
	var chars := DataLoader.new().module("characters")
	var defs: Dictionary = chars.get("CHAR_DEF", {})
	for id in chars.get("CHAR_LIST", []):
		var d: Dictionary = defs.get(String(id), {})
		var sel := String(id) == character
		var id_c := String(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		# 角色立绘（`char_<id>.png`）——缺失时整块跳过，不影响选人
		var portrait := Sprites.get_tex("char_" + String(id))
		if portrait != null:
			var holder := CenterContainer.new()
			holder.custom_minimum_size = Vector2(96, 96)
			var tr := TextureRect.new()
			tr.texture = portrait
			tr.custom_minimum_size = Vector2(88, 88)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if not sel:
				tr.modulate = Color(0.62, 0.66, 0.72)      # 未选中的压暗，选中的高亮
			holder.add_child(tr)
			row.add_child(holder)
		var pick := _option_button(String(d.get("name", id)), sel, Color("#8fe0ff"),
			func() -> void:
				character = id_c
				rebuild(), Vector2(200, 56))
		row.add_child(pick)
		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(820, 0)
		var tag := Label.new()
		tag.text = String(d.get("tagline", ""))
		tag.add_theme_color_override("font_color", Color("#8fe0ff") if sel else Color("#8ba0bb"))
		info.add_child(tag)
		var base: Dictionary = d.get("base", {})
		info.add_child(_sub("生命 %d · 伤害 %.2f · 护甲 %d · 移速 %.2f · 暴击 %d%%" % [
			int(base.get("hp", 0)), float(base.get("damage", 1.0)), int(base.get("armor", 0)),
			float(base.get("speed", 1.0)), int(round(float(base.get("critChance", 0.0)) * 100.0))], 820.0))
		var passive: Dictionary = d.get("passive", {})
		var keys: Array = passive.keys()
		keys.sort()
		var parts: Array = []
		var shown := 0
		for k in keys:
			if shown >= 5:
				break
			var v = passive[k]
			if v is bool:
				if GdMath.truthy(v):
					parts.append(String(k))
					shown += 1
			elif v is float or v is int:
				parts.append("%s %s" % [String(k), str(v)])
				shown += 1
		info.add_child(_sub("被动：" + (" · ".join(parts) if not parts.is_empty() else "—"), 820.0))
		row.add_child(info)
		box.add_child(row)
		box.add_child(_spacer(8))
	_footer(box, Screen.MODE, "下一步：选星球 →", func() -> void: goto(Screen.PLANET))


# ---------- 星球与种子 ----------
#
# 玩家要的样子：**星球贴图居中展示，名字标在星球下方，左右滑选**，
# 并且把难度分级直接写在星球下面。
# 星球贴图按**难度档位**取（5 张，`planet_1..5`）—— 一眼就能看出这颗星球有多凶。
func _planet_name(i: int) -> String:
	var mod: Dictionary = DataLoader.new().module("planets")
	var names: Array = mod.get("PLANET_NAMES", [])
	var suffix: Array = mod.get("PLANET_SUFFIX", [])
	if names.is_empty():
		return "未知星球"
	return "%s·%s" % [String(names[i % names.size()]), String(suffix[i % maxi(1, suffix.size())])]


func planet_step(dir: int) -> void:
	var mod: Dictionary = DataLoader.new().module("planets")
	var n: int = maxi(1, (mod.get("PLANET_NAMES", []) as Array).size())
	planet_index = int(fposmod(float(planet_index + dir), float(n)))
	rebuild()


func _build_planet(box: Node) -> void:
	box.add_child(_title("选择星球", 30))
	box.add_child(_sub("点 ◀ ▶ 或按键盘左右方向键切换星球；星球下方标着这一局的难度与倍率。"))

	var stage := HBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", 20)
	stage.add_child(_btn("◀", func() -> void: planet_step(-1), Vector2(52, 150)))

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size = Vector2(340, 0)
	col.add_theme_constant_override("separation", 2)
	var holder := CenterContainer.new()
	# 星球 170px：720p 屏幕要塞得下「星球 + 名字 + 难度 + 说明 + 种子行 + 按钮」，
	# 300px 那版直接把底部整行挤出画面（截图实测）
	holder.custom_minimum_size = Vector2(175, 175)
	var lv := PlanetDiff.level_for(planet_index)
	var tex := Sprites.get_tex("planet_%d" % lv)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(170, 170)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		holder.add_child(tr)
	else:
		# 贴图缺失：画一个带星球名的占位圆（仍然能玩、能选）
		var ph := Label.new()
		ph.text = "（星球贴图 planet_%d 缺失）" % lv
		ph.add_theme_color_override("font_color", Color("#6b7684"))
		holder.add_child(ph)
	col.add_child(holder)
	# 名字标在**星球正下方**
	var name_l := Label.new()
	name_l.text = _planet_name(planet_index)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", Color("#e8eef7"))
	col.add_child(name_l)
	# 难度分级
	var diff_l := Label.new()
	diff_l.text = "难度 %d 级 · %s" % [lv, PlanetDiff.name_of(planet_index)]
	diff_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diff_l.add_theme_font_size_override("font_size", 17)
	diff_l.add_theme_color_override("font_color", Color("#ffba4c"))
	col.add_child(diff_l)
	var mod_l := Label.new()
	mod_l.text = PlanetDiff.summary(planet_index)
	mod_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mod_l.add_theme_font_size_override("font_size", 14)
	mod_l.add_theme_color_override("font_color", Color("#8fe0ff"))
	col.add_child(mod_l)
	var desc_l := Label.new()
	desc_l.text = PlanetDiff.desc_of(planet_index)
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.custom_minimum_size = Vector2(340, 0)
	desc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_l.add_theme_font_size_override("font_size", 13)
	desc_l.add_theme_color_override("font_color", Color("#8ba0bb"))
	col.add_child(desc_l)
	stage.add_child(col)
	stage.add_child(_btn("▶", func() -> void: planet_step(1), Vector2(52, 150)))
	box.add_child(stage)

	# 底部：星球序号 + 种子（一行塞下，省高度）
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 10)
	# ⚠️ 这里不能用 `_sub()`：它带自动换行，在 HBox 里会被压成「一列一个字」，
	# 整行被撑得很高、把下面的按钮顶出屏幕（截图实测）。行内标签一律不换行。
	var idx_l := Label.new()
	idx_l.text = "第 %d / 12 号星球" % (planet_index + 1)
	idx_l.add_theme_font_size_override("font_size", 15)
	idx_l.add_theme_color_override("font_color", Color("#8ba0bb"))
	srow.add_child(idx_l)
	var seed_edit := LineEdit.new()
	seed_edit.text = seed_text
	seed_edit.custom_minimum_size = Vector2(300, 32)
	seed_edit.text_changed.connect(func(t: String) -> void: seed_text = t)
	srow.add_child(seed_edit)
	srow.add_child(_btn("随机种子", func() -> void:
		seed_text = random_seed_text()
		rebuild(), Vector2(110, 32)))
	box.add_child(srow)
	var summary := Label.new()
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 13)
	summary.text = "即将开始：%s · %s · %s · 难度 %d 级 · 种子 %s" % [
		String(_mode_def().get("name", mode)), String(_char_def().get("name", character)),
		_planet_name(planet_index), lv, seed_text]
	summary.add_theme_color_override("font_color", Color("#6ee7a8"))
	box.add_child(summary)
	_footer(box, Screen.CHARACTER, "开始游戏 →",
		func() -> void: start_requested.emit(start_params()))


func _mode_def() -> Dictionary:
	var defs: Dictionary = DataLoader.new().module("modes").get("MODE_DEF", {})
	return defs.get(mode, {})


func _char_def() -> Dictionary:
	var defs: Dictionary = DataLoader.new().module("characters").get("CHAR_DEF", {})
	return defs.get(character, {})


## 这一份参数就是喂给世界生成与属性装配的东西
func start_params() -> Dictionary:
	var mods := DataLoader.new().module("modes")
	var mdef: Dictionary = mods.get("MODE_DEF", {}).get(mode, {})
	var chars := DataLoader.new().module("characters")
	var cdef: Dictionary = chars.get("CHAR_DEF", {}).get(character, {})
	var w: Dictionary = mdef.get("world", {})
	return {
		"mode": mode,
		"character": character,
		"seed": seed_text if seed_text != "" else random_seed_text(),
		"planetIndex": planet_index,
		# 0 是有意义的取值（塔防模式不撒巢穴）—— 用只认「键缺失」的 num()
		"nestScale": DataLoader.num(w, "nestScale", 1.0),
		"poiScale": DataLoader.num(w, "poiScale", 1.0),
		"compact": GdMath.truthy(w.get("compact", false)),
		"hasPlayer": GdMath.truthy(mdef.get("hasPlayer", true)),
		"fieldRadius": DataLoader.num(mdef, "fieldRadius", 900.0),
		"startResources": mdef.get("startResources", {}),
		"base": cdef.get("base", {}),
		"passive": cdef.get("passive", {}),
	}


# ---------- 生成中 ----------
func _build_loading(box: Node) -> void:
	box.add_child(_spacer(180))
	box.add_child(_title("正在生成世界…", 36))
	box.add_child(_spacer(10))
	box.add_child(_sub(_loading_msg))
	box.add_child(_spacer(6))
	box.add_child(_sub(_loading_detail))
	box.add_child(_spacer(18))
	box.add_child(_sub("Godot 版的世界生成约 4~5 秒（每个地块要算 5 层噪声），这一步没法拆帧 —— 先给个明确的等待界面，比卡住好。"))


func show_loading(detail: String) -> void:
	_loading_detail = detail
	goto(Screen.LOADING)


# ---------- 设置 ----------
func _build_settings(box: Node) -> void:
	box.add_child(_title("设置", 32))
	box.add_child(_sub("这里只放开局前常用的几项；游戏内 Esc 面板里还有完整的设置页。"))
	box.add_child(_spacer(12))
	var st := Settings.new()
	st.load_settings()
	box.add_child(_row([_btn("窗口模式：%s" % ("全屏" if GdMath.truthy(st.get_value("fullscreen")) else "窗口"),
		func() -> void:
			var on := not GdMath.truthy(st.get_value("fullscreen"))
			st.set_value("fullscreen", on)
			st.apply(null, true)
			st.save()
			rebuild(), Vector2(220, 36))]))
	box.add_child(_row([_btn("音效：%d%%" % int(round(float(st.get_value("sfxVolume")) * 100.0)),
		func() -> void:
			var v := float(st.get_value("sfxVolume")) + 0.25
			if v > 1.01:
				v = 0.0
			st.set_value("sfxVolume", v)
			st.save()
			rebuild(), Vector2(220, 36))]))
	box.add_child(_spacer(16))
	box.add_child(_row([_btn("← 返回", func() -> void: goto(Screen.TITLE), Vector2(160, 36))]))


# ---------- 选降落点（对应 HTML 版的整屏地图交互）----------
func show_landing(world: GdWorld) -> void:
	landing_world = world
	landing_map = LandingMap.new()
	landing_map.setup(world)
	goto(Screen.LANDING)


func _build_landing(box: Node) -> void:
	# ⚠️ 这一屏要**塞进 1280×720**：之前地图 560px + 标题 + 底部 footer
	#    把「降落」按钮挤到了可视区外面 —— 玩家能点地图，却按不到降落（真实反馈）。
	#    现在改成：地图 430px，按钮放在右栏里（不依赖全局 footer）。
	box.add_child(_title("选择降落点", 28))
	box.add_child(_sub("点地图任意位置选点，或用右边 1-4 号推荐点。绿圈 = 推荐点，红点 = 虫巢，黄方块 = 废弃基地。"))
	box.add_child(_spacer(6))
	if landing_map == null or landing_world == null:
		box.add_child(_sub("（世界还没生成）"))
		return
	const MAP_SIZE := 430.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var map := Control.new()
	map.custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	var mm := landing_map
	map.draw.connect(func() -> void:
		mm.draw_map(map, Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)))
	map.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mp := (ev as InputEventMouseButton).position
			var wp := mm.map_to_world(mp, Vector2(MAP_SIZE, MAP_SIZE))
			var best := -1
			var best_d := 30.0 * float(Cfg.TILE)   # 30 格内吸附到推荐点
			for i in mm.sites.size():
				var s: Dictionary = mm.sites[i]
				var d := Vector2(float(s["x"]), float(s["y"])).distance_to(wp)
				if d < best_d:
					best_d = d
					best = i
			if best >= 0:
				mm.selected = best
				picked_free = Vector2(-1, -1)   # 吸附到推荐点时必须清掉自由点，否则降落还用旧坐标
			else:
				picked_free = wp
			mm.hover = wp
			map.queue_redraw()
			rebuild())
	row.add_child(map)
	# 右栏：先给「降落」，再给信息与推荐点（保证按钮永远在可视区内）
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(560, 0)
	side.add_theme_constant_override("separation", 4)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	var land_btn := _btn("▶ 降落", func() -> void: landing_confirmed.emit(_selected_site()), Vector2(180, 40))
	land_btn.add_theme_color_override("font_color", Color("#6ee7a8"))
	btns.add_child(land_btn)
	btns.add_child(_btn("← 返回", func() -> void: goto(Screen.PLANET), Vector2(120, 40)))
	btns.add_child(_btn("随机换一处", func() -> void:
		landing_map.selected = (landing_map.selected + 1) % maxi(1, landing_map.sites.size())
		picked_free = Vector2(-1, -1)
		rebuild(), Vector2(140, 40)))
	side.add_child(btns)
	side.add_child(_spacer(6))
	var sel := _selected_site()
	var free := picked_free.x >= 0.0
	side.add_child(_sub("当前选择：%s" % ("自选坐标" if free else String(sel.get("tierName", "—")))))
	side.add_child(_sub("坐标  %d, %d" % [int(sel.get("tx", 0)), int(sel.get("ty", 0))]))
	side.add_child(_sub("生物群系  %s   ·   危险度  %s" % [String(sel.get("biomeName", "—")), String(sel.get("tierName", "—"))]))
	side.add_child(_sub("1000 内虫巢  %d   ·   资源丰度  ×%.2f" % [int(sel.get("nestNear", 0)), float(sel.get("richness", 1.0))]))
	side.add_child(_sub("地形危险  ×%.2f   ·   开阔度  %d%%" % [float(sel.get("hazard", 1.0)), int(round(float(sel.get("openSpace", 0.0)) * 100.0))]))
	side.add_child(_sub("✓ 可以在这里降落" if not _site_blocked(sel) else "✗ 这里地形太挤，换一处"))
	side.add_child(_spacer(4))
	for i in landing_map.sites.size():
		var s2: Dictionary = landing_map.sites[i]
		var b := _option_button("%d. %s · %s" % [i + 1, String(s2.get("tierName", "")),
			String(s2.get("biomeName", ""))], (not free) and i == landing_map.selected, Color("#6ee7a8"),
			func() -> void:
				landing_map.selected = i
				picked_free = Vector2(-1, -1)
				rebuild(), Vector2(540, 26))
		side.add_child(b)
	row.add_child(side)
	box.add_child(row)

## 玩家在地图上自由点选的位置（没有吸附到推荐点时用）
var picked_free := Vector2(-1, -1)


func _selected_site() -> Dictionary:
	if landing_map == null or landing_map.sites.is_empty():
		return {}
	if picked_free.x >= 0.0:
		var s: Dictionary = (landing_map.sites[landing_map.selected] as Dictionary).duplicate()
		s["x"] = picked_free.x
		s["y"] = picked_free.y
		s["tx"] = int(picked_free.x / float(Cfg.TILE))
		s["ty"] = int(picked_free.y / float(Cfg.TILE))
		return s
	return landing_map.sites[landing_map.selected]


func _site_blocked(site: Dictionary) -> bool:
	if landing_world == null:
		return true
	return landing_world.circle_blocked(float(site.get("x", 0.0)), float(site.get("y", 0.0)), 40.0)