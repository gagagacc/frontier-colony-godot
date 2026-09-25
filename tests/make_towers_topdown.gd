## 程序化生成**正俯视**炮塔贴图 —— 保底方案（生图模型始终画不出严格正俯视）。
##
##   godot --headless --path . --script res://tests/make_towers_topdown.gd
##
## ## 为什么要有这个
##
## 玩家连着两轮反馈「炮塔还是斜着的俯视图，不是炮管正上方的俯视图」。生图模型无论怎么
## 提示都会画出 3/4 立体感（还会跑成蓝图线稿风）。而炮塔要**跟着瞄准角旋转**，
## 视角一歪，旋转就是错的 —— 所以这一项**几何正确性优先于绘画感**：
## 直接按俯视图的定义画：同心圆底座 + 一条**从圆心笔直指向画面正上方**的矩形炮管。
##
## 画法沿用项目里已有的路子（`tile_atlas.gd` 也是程序化画地块）：
## 逐像素合成 → 存 PNG。这样：
##   · 炮管方向**严格是 -90°**，标定表量出来就是 90°，旋转不会歪；
##   · 11 座塔的轮廓各不相同（管数、管长、口径、附件），一眼能区分；
##   · 想调色/调细节就是改这里的常量，不用再排队等生图。
extends SceneTree

const SIZE := 192           # 输出边长（游戏里画 44px，留足余量）
const OUT_DIR := "res://assets/sprites"

# 配色（与生图素材的深蓝灰金属 + 青色发光一致）
const C_BASE := Color("#3b4450")
const C_BASE_DARK := Color("#252b34")
const C_BASE_LIGHT := Color("#525d6c")
const C_EDGE := Color("#1a1e24")
const C_BARREL := Color("#4a5563")
const C_BARREL_LIGHT := Color("#6b7889")
const C_GLOW := Color("#59d8ff")
const C_ACCENT := Color("#8fe0ff")


func _initialize() -> void:
	var towers := {
		# len 是**相对底座半径 R 的倍数**：必须 > 1.0，炮管才会伸出底座露出来
		# （第一版写成 0.6 左右，结果炮管全缩在圆盘里，看着像底座上插了根小棍）
		"sentry":        { "barrels": 1, "len": 1.35, "wid": 0.26, "muzzle": 0.30, "accent": C_GLOW },
		"gatling":       { "barrels": 6, "len": 1.15, "wid": 0.13, "muzzle": 0.16, "accent": Color("#ffba4c") },
		"mortar":        { "barrels": 1, "len": 0.95, "wid": 0.46, "muzzle": 0.56, "accent": Color("#ff9f4c") },
		"rail":          { "barrels": 2, "len": 1.70, "wid": 0.14, "muzzle": 0.17, "gap": 0.24, "accent": C_ACCENT },
		"tesla":         { "barrels": 0, "len": 0.0, "wid": 0.0, "muzzle": 0.0, "coil": true, "accent": C_GLOW },
		"cryo":          { "barrels": 1, "len": 1.25, "wid": 0.34, "muzzle": 0.42, "crystal": true, "accent": Color("#8fd8ff") },
		"flameTower":    { "barrels": 1, "len": 1.10, "wid": 0.38, "muzzle": 0.48, "vents": true, "accent": Color("#ff7a3c") },
		"sniper":        { "barrels": 1, "len": 1.95, "wid": 0.16, "muzzle": 0.20, "accent": Color("#c9d4e0") },
		"dronePlatform": { "barrels": 0, "len": 0.0, "wid": 0.0, "muzzle": 0.0, "pad": true, "accent": Color("#c08cff") },
		"magneticRail":  { "barrels": 2, "len": 1.55, "wid": 0.24, "muzzle": 0.30, "gap": 0.34, "heavy": true, "accent": Color("#c08cff") },
		"forceField":    { "barrels": 0, "len": 0.0, "wid": 0.0, "muzzle": 0.0, "dome": true, "accent": Color("#c08cff") },
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for id in towers.keys():
		var img := _draw_tower(towers[id])
		var path := ProjectSettings.globalize_path(OUT_DIR.path_join("tower_%s.png" % id))
		img.save_png(path)
		print("  ✓ tower_%s.png" % id)
	print("TOWERS_OK 程序化正俯视炮塔 %d 张 → %s" % [towers.size(), OUT_DIR])
	quit(0)


func _draw_tower(cfg: Dictionary) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(SIZE) / 2.0
	# 底座**下移**：炮管要往画面上方伸出 1~2 倍底座半径，居中画会被画布裁掉
	var cy := float(SIZE) * 0.68
	var R := float(SIZE) * 0.30          # 底座半径

	# ① 底座投影
	_disc(img, cx, cy + R * 0.06, R * 1.02, Color(0, 0, 0, 0.30))
	# ② 底座：外圈 + 内圈 + 装甲分块
	_disc(img, cx, cy, R, C_BASE)
	_ring(img, cx, cy, R, 3.0, C_EDGE)
	_disc(img, cx, cy, R * 0.82, C_BASE_DARK)
	_ring(img, cx, cy, R * 0.82, 2.0, C_BASE_LIGHT)
	# 装甲分块（按角度切 8 块，深浅交替 —— 俯视看底座才不是一块死板圆盘）
	var seg := 8
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		if i % 2 == 0:
			continue
		_arc_band(img, cx, cy, R * 0.86, R, a0, a1, C_BASE_LIGHT)
	# 铆钉
	for i in seg:
		var a := TAU * float(i) / float(seg) + PI / float(seg)
		_disc(img, cx + cos(a) * R * 0.91, cy + sin(a) * R * 0.91, 2.2, C_EDGE)

	# ③ 炮塔本体（转台）
	_disc(img, cx, cy, R * 0.52, C_BASE_LIGHT)
	_ring(img, cx, cy, R * 0.52, 2.0, C_EDGE)

	# ④ 炮管 / 特征件（**全部朝画面正上方**）
	var barrels := int(cfg.get("barrels", 0))
	if barrels > 0:
		var blen := R * float(cfg["len"])
		var bw := R * float(cfg["wid"])
		var mz := R * float(cfg["muzzle"])
		var gap := R * float(cfg.get("gap", 0.0))
		for i in barrels:
			var off := 0.0
			if barrels > 1:
				off = (float(i) - float(barrels - 1) * 0.5) * (gap if gap > 0.0 else bw * 1.35)
			# 加特林是环形排布
			if barrels > 2:
				var a := TAU * float(i) / float(barrels)
				_barrel(img, cx + cos(a) * bw * 1.5, cy + sin(a) * bw * 1.5, blen, bw, mz, cfg)
			else:
				_barrel(img, cx + off, cy, blen, bw, mz, cfg)
	elif GdMath.truthy(cfg.get("coil", false)):
		# 电弧线圈：同心环 + 四根电极，没有炮管（旋转对称）
		for k in 3:
			_ring(img, cx, cy, R * (0.22 + float(k) * 0.09), 2.0, C_ACCENT)
		for i in 4:
			var a2 := TAU * float(i) / 4.0 + PI / 4.0
			_disc(img, cx + cos(a2) * R * 0.40, cy + sin(a2) * R * 0.40, 4.0, C_GLOW)
	elif GdMath.truthy(cfg.get("crystal", false)):
		_barrel(img, cx, cy, R * 0.46, R * 0.13, R * 0.17, cfg)
		for i in 3:
			var a3 := -PI / 2.0 + (float(i) - 1.0) * 0.42
			_tri(img, cx + cos(a3) * R * 0.30, cy + sin(a3) * R * 0.30,
				R * 0.20, a3 - PI / 2.0, C_ACCENT)
	elif GdMath.truthy(cfg.get("vents", false)):
		_barrel(img, cx, cy, R * 0.42, R * 0.15, R * 0.20, cfg)
		for i in 3:
			var a4 := -PI / 2.0 + (float(i) - 1.0) * 0.55
			_line(img, cx + cos(a4) * R * 0.30, cy + sin(a4) * R * 0.30,
				cx + cos(a4) * R * 0.48, cy + sin(a4) * R * 0.48, 2.0, C_EDGE)
	elif GdMath.truthy(cfg.get("pad", false)):
		# 无人机停机坪：圆盘 + 四个旋翼吊舱 + 中央标识
		_disc(img, cx, cy, R * 0.70, C_BASE_LIGHT)
		_ring(img, cx, cy, R * 0.70, 2.0, C_EDGE)
		for i in 4:
			var a5 := TAU * float(i) / 4.0 + PI / 4.0
			_disc(img, cx + cos(a5) * R * 0.58, cy + sin(a5) * R * 0.58, R * 0.14, C_BASE_DARK)
			_ring(img, cx + cos(a5) * R * 0.58, cy + sin(a5) * R * 0.58, R * 0.14, 1.5,
				Color(cfg["accent"]))
		_tri(img, cx, cy - R * 0.10, R * 0.16, -PI / 2.0, Color(cfg["accent"]))
	elif GdMath.truthy(cfg.get("dome", false)):
		# 力场发生器：外环 + 内部能量穹顶（旋转对称）
		_ring(img, cx, cy, R * 0.78, 3.0, Color(cfg["accent"]))
		for k2 in 3:
			_ring(img, cx, cy, R * (0.30 + float(k2) * 0.16), 1.5,
				Color(cfg["accent"].r, cfg["accent"].g, cfg["accent"].b, 0.55))
		for i in 4:
			_disc(img, cx + cos(TAU * float(i) / 4.0) * R * 0.62,
				cy + sin(TAU * float(i) / 4.0) * R * 0.62, 3.0, C_GLOW)

	# ⑤ 顶部高光（俯视图的光从正上方来，所以是中心偏左上的一层柔光）
	_soft_light(img, cx, cy, R * 0.9)
	# ⑥ 裁到内容并居中放回正方形画布 —— 旋转时以**贴图中心**为支点，
	#    不居中的话炮塔会绕着一个偏心的点转（炮口绕着底座甩）
	return _trim_center(img)


## 裁到不透明内容的包围盒，再等比缩放居中放进 SIZE×SIZE 的正方形
func _trim_center(img: Image) -> Image:
	var x0 := SIZE
	var y0 := SIZE
	var x1 := -1
	var y1 := -1
	for y in SIZE:
		for x in SIZE:
			if img.get_pixel(x, y).a > 0.05:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < x0 or y1 < y0:
		return img
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	var cell := img.get_region(Rect2i(x0, y0, w, h))
	var k := float(SIZE) / float(maxi(w, h))
	var nw := maxi(1, int(round(float(w) * k)))
	var nh := maxi(1, int(round(float(h) * k)))
	var scaled := Image.create(w, h, false, Image.FORMAT_RGBA8)
	scaled.blit_rect(cell, Rect2i(0, 0, w, h), Vector2i.ZERO)
	scaled.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(scaled, Rect2i(0, 0, nw, nh), Vector2i((SIZE - nw) / 2, (SIZE - nh) / 2))
	return out


## 一根炮管：矩形管身 + 末端炮口环（**笔直朝上**，世界坐标里角度严格 -90°）
func _barrel(img: Image, x: float, y: float, length: float, width: float, muzzle: float,
	cfg: Dictionary) -> void:
	var half := width * 0.5
	var top := y - length
	# 管身（带一点左右明暗，仍是俯视的顶面）
	for py in range(int(top), int(y) + 1):
		for px in range(int(x - half), int(x + half) + 1):
			if px < 0 or py < 0 or px >= SIZE or py >= SIZE:
				continue
			var t := (float(px) - (x - half)) / maxf(1.0, width)
			var c := C_BARREL.lerp(C_BARREL_LIGHT, clampf(t * 0.8 + 0.1, 0.0, 1.0))
			_put(img, px, py, c)
	# 管身描边
	_rect_outline(img, x - half, top, width, length, 1.6, C_EDGE)
	# 炮口（同心环 + 内孔）
	if muzzle > 1.0:
		_disc(img, x, top + muzzle * 0.35, muzzle, C_BARREL_LIGHT)
		_ring(img, x, top + muzzle * 0.35, muzzle, 2.0, C_EDGE)
		_disc(img, x, top + muzzle * 0.35, muzzle * 0.45, Color("#12161c"))
		# 炮口发光（能量武器观感）
		if GdMath.truthy(cfg.get("heavy", false)) or GdMath.truthy(cfg.get("crystal", false)):
			_disc(img, x, top + muzzle * 0.35, muzzle * 0.28, Color(cfg["accent"]))


func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	var old := img.get_pixel(x, y)
	img.set_pixel(x, y, old.lerp(c, c.a) if c.a < 1.0 else c)


func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	var r2 := r * r
	for py in range(maxi(0, int(cy - r)), mini(SIZE - 1, int(cy + r)) + 1):
		for px in range(maxi(0, int(cx - r)), mini(SIZE - 1, int(cx + r)) + 1):
			var dx := float(px) - cx
			var dy := float(py) - cy
			if dx * dx + dy * dy <= r2:
				_put(img, px, py, c)


func _ring(img: Image, cx: float, cy: float, r: float, w: float, c: Color) -> void:
	var inner := (r - w) * (r - w)
	var outer := (r + w) * (r + w)
	for py in range(maxi(0, int(cy - r - w)), mini(SIZE - 1, int(cy + r + w)) + 1):
		for px in range(maxi(0, int(cx - r - w)), mini(SIZE - 1, int(cx + r + w)) + 1):
			var dx := float(px) - cx
			var dy := float(py) - cy
			var d2 := dx * dx + dy * dy
			if d2 >= inner and d2 <= outer:
				_put(img, px, py, c)


func _arc_band(img: Image, cx: float, cy: float, r0: float, r1: float,
	a0: float, a1: float, c: Color) -> void:
	for py in range(maxi(0, int(cy - r1)), mini(SIZE - 1, int(cy + r1)) + 1):
		for px in range(maxi(0, int(cx - r1)), mini(SIZE - 1, int(cx + r1)) + 1):
			var dx := float(px) - cx
			var dy := float(py) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d < r0 or d > r1:
				continue
			var a := fposmod(atan2(dy, dx) - a0, TAU)
			if a <= (a1 - a0):
				_put(img, px, py, c)


func _line(img: Image, x0: float, y0: float, x1: float, y1: float, w: float, c: Color) -> void:
	var steps := int(maxf(absf(x1 - x0), absf(y1 - y0))) + 1
	for i in steps + 1:
		var t := float(i) / float(steps)
		_disc(img, lerpf(x0, x1, t), lerpf(y0, y1, t), w * 0.5, c)


func _rect_outline(img: Image, x: float, y: float, w: float, h: float, t: float, c: Color) -> void:
	_line(img, x, y, x + w, y, t, c)
	_line(img, x, y, x, y + h, t, c)
	_line(img, x + w, y, x + w, y + h, t, c)


## 一个朝指定方向的小三角（装饰用）
func _tri(img: Image, x: float, y: float, size: float, dir: float, c: Color) -> void:
	for i in int(size * 2.0):
		var t := float(i) / maxf(1.0, size * 2.0)
		var w := size * (1.0 - t)
		var px := x + cos(dir) * size * t
		var py := y + sin(dir) * size * t
		_disc(img, px, py, w * 0.5, c)


## 中心柔光（正上方打光）
func _soft_light(img: Image, cx: float, cy: float, r: float) -> void:
	for py in range(maxi(0, int(cy - r)), mini(SIZE - 1, int(cy + r)) + 1):
		for px in range(maxi(0, int(cx - r)), mini(SIZE - 1, int(cx + r)) + 1):
			var dx := (float(px) - cx + r * 0.25) / r
			var dy := (float(py) - cy + r * 0.25) / r
			var d := sqrt(dx * dx + dy * dy)
			if d >= 1.0:
				continue
			var a := (1.0 - d) * 0.16
			_put(img, px, py, Color(1.0, 1.0, 1.0, a))
