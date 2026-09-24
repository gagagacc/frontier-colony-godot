## 贴图加载器 —— 逻辑名 → `res://assets/...`，带缓存，**找不到就返回 null**。
##
## 与 JS 版 `assets/manifest.json` 同一套思路：贴图是可选的，
## 有就贴图、没有就退回程序化绘制 —— 这样才能一块一块换而不破坏游戏。
##
## 命名约定（文件都在 `godot/assets/` 下）：
##   sprites/tower_light.png      轻型炮塔
##   sprites/tower_heavy.png      重型炮塔
##   sprites/enemy_1..8.png       怪物（来自科技感 RTS 包的单位）
##   sprites/structure_1..6.png   建筑
##   sprites/bullet|rocket|flame.png  弹丸
##   sprites/prop_*.png           道具（箱子/地雷/草丛）
class_name Sprites

static var _cache: Dictionary = {}


## 按逻辑名取贴图；不存在返回 null
static func get_tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	for dir in ["sprites", "tiles", "ui"]:
		var path := "res://assets/%s/%s.png" % [dir, name]
		if ResourceLoader.exists(path):
			var tex := load(path)
			if tex is Texture2D:
				_cache[name] = tex
				return tex
	_cache[name] = null
	return null


## 塔的贴图：**一塔一张**（由本地生图模型生成的素材，4×4 素材表切出来的）。
##
## 找不到专属贴图时退回原来那两张 Kenney 通用炮塔 —— 所以少一两张也不会开天窗。
static func tower_tex(id: String) -> Texture2D:
	var own := get_tex("tower_" + id)
	if own != null:
		return own
	var heavy := ["mortar", "rail", "tesla", "cryo", "flameTower", "sniper", "magneticRail", "forceField"]
	return get_tex("tower_heavy" if heavy.has(id) else "tower_light")


## 炮管朝向标定表 —— 由 `tests/probe_barrel.gd` 从贴图里量出来，写在 `data/barrel_angles.json`。
##
## ## 为什么不是常量
##
## 贴图上的炮管是朝右上画的，画到场上要按瞄准角反向旋转。补偿量必须等于**该贴图里炮管的仰角**，
## 否则炮管和目标差一个固定夹角（玩家反馈过「炮管和打击方向不一致」）。而生成素材的仰角
## **每张都不一样**（实测 59.7°~69.9°，中位 64.6°），写死一个常量必然有几座塔是歪的。
##
## 值为 **-1** 表示「左右镜像对称、根本没有炮管」的贴图（力场穹顶、无人机平台）——
## 这类不该跟着目标转，否则穹顶会原地打转。
const DEFAULT_BARREL_OFFSET := PI * 0.33      # 标定表缺失时的兜底
const NO_BARREL := -1.0

static var _barrel: Dictionary = {}
static var _barrel_loaded := false


static func barrel_offset(id: String) -> float:
	if not _barrel_loaded:
		_barrel_loaded = true
		var f := FileAccess.open("res://data/barrel_angles.json", FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_barrel = parsed
	return float(_barrel.get("tower_" + id, DEFAULT_BARREL_OFFSET))


## 给测试用：整张标定表
static func barrel_table() -> Dictionary:
	barrel_offset("__probe__")      # 触发一次加载
	return _barrel


## 怪物的贴图 —— 玩家要的是「**像红警2坦克那样，移动时变形**」，所以：
##
## ## 一个物种三视图
##
## `enemy_<kind>_s.png`  正俯视（从正上方往下看，朝下/面向镜头走时用）
## `enemy_<kind>_d.png`  侧 45 度俯视（背对镜头、朝上走时用）
## `enemy_<kind>_f.png`  侧俯视（朝左右走时用，朝左靠左右镜像）
##
## ## 为什么不旋转贴图
##
## 有机生物整体旋转一眼就能看出「贴图被转过去了」（炮塔那种圆底座才适合旋转）。
## 换视图 + 镜像才有「转身」的感觉，而且三视图本来就画着不同透视。
##
## 找不到三视图时**退回单张老素材**（按朝向旋转），再退回按种类哈希分配 —— 逐级兜底，
## 换素材的过程中不会开天窗。
const ENEMY_VIEWS := ["s", "d", "f"]        # 正俯视 / 侧45度 / 侧俯视


static func enemy_view_tex(kind: String, view: int) -> Texture2D:
	return get_tex("enemy_%s_%s" % [kind, ENEMY_VIEWS[clampi(view, 0, ENEMY_VIEWS.size() - 1)]])


## 朝向角 → [视图序号, 是否左右镜像]
##
## 角度用 Godot 约定（y 轴向下）：0=右、PI/2=下（朝镜头）、-PI/2=上（背对镜头）、±PI=左。
## 八向映射：朝下 → 正俯视；朝上 → 侧 45 度；朝左右 → 侧俯视（朝左镜像）。
## 对角方向自然落到相邻视图上，看起来就是「半转身」。
static func enemy_facing_view(angle: float) -> Array:
	var deg := rad_to_deg(wrapf(angle, -PI, PI))
	if deg >= 45.0 and deg < 135.0:
		return [0, false]          # 朝下（面向镜头）：正俯视
	if deg <= -45.0 and deg > -135.0:
		return [1, false]          # 朝上（背对镜头）：侧 45 度俯视
	if deg >= 135.0 or deg < -135.0:
		return [2, true]           # 朝左：侧俯视 + 左右镜像
	return [2, false]              # 朝右：侧俯视


## 单张老贴图（没有三视图时的兜底）：按种类**首次出现顺序**发号 ——
## 同一种怪永远同一张，看起来才像「一个物种」。
static var _kind_slot: Dictionary = {}      # kind -> 贴图序号
static var _next_slot := 1


static func enemy_tex(kind: String) -> Texture2D:
	# ⚠️ 不要用 hash % 16 分配：种类少的时候会撞（同屏的怪全是同一张）。
	if not _kind_slot.has(kind):
		_kind_slot[kind] = _next_slot
		_next_slot = (_next_slot % 16) + 1
	var own := get_tex("enemy_%d" % int(_kind_slot[kind]))
	if own != null:
		return own
	return get_tex("enemy_%d" % (int(abs(kind.hash()) % 8) + 1))


## 道具贴图：**一类一张**（本地生图模型出的素材，4×4 素材表切出来的）。
##
## 优先按道具类型 id 找专属贴图（`prop_ironNode.png` / `prop_crystalNode.png` …）；
## 找不到才退回原来那三张 Kenney 通用件（箱子/地雷/草丛）——
## 所以分批换素材时，没换的那些还是老样子，不会开天窗。
##
## 为什么值得一张一张换：原先 14 种道具**全靠程序化形状**（圆/三角/方块 + 底色）画，
## 玩家看到的是一片色块（「补全这些色块」就是说的这个）。
static func prop_tex(key: String) -> Texture2D:
	var own := get_tex("prop_" + key)
	if own != null:
		return own
	var k := key.to_lower()
	if k.contains("crate") or k.contains("supply") or k.contains("wreck") or k.contains("cache"):
		return get_tex("prop_crate_green" if k.hash() % 2 == 0 else "prop_crate_wood")
	if k.contains("mine") or k.contains("spike"):
		return get_tex("prop_mine")
	if k.contains("tuft") or k.contains("grass") or k.contains("bush") or k.contains("moss"):
		return get_tex("prop_grass_tuft")
	return null


## 建筑贴图
static func structure_tex(idx: int) -> Texture2D:
	return get_tex("structure_%d" % (clampi(idx, 1, 6)))


## 画一张居中的贴图（自动缩放到目标尺寸）
static func draw_centered(c: CanvasItem, tex: Texture2D, center: Vector2, size_px: float,
	tint: Color = Color.WHITE) -> void:
	if tex == null:
		return
	var s := tex.get_size()
	var k := size_px / maxf(s.x, s.y)
	var draw_size := s * k
	c.draw_texture_rect(tex, Rect2(center - draw_size / 2.0, draw_size), false, tint)
