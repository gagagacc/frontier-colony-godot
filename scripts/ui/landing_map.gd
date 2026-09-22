## 降落点地图 —— 对应 JS 的「选择降落点」整屏。
##
## 玩家实测反馈：HTML 版这一屏是**整屏地图交互**（点地图选点 + 4 个推荐点 +
## 坐标/生物群系/危险度/资源丰度/开阔度），Godot 版完全没有，直接自动落地。
##
## 做法：世界只有 152×152 格，先烘一张 152×152 的小图（每格一个像素，按群系取色），
## 之后每帧只是把这张图放大画出来 —— 比逐格 draw_rect 快两个数量级。
class_name LandingMap

var world: GdWorld = null
var image: Image = null
var tex: ImageTexture = null
var sites: Array = []
var selected := 0
var hover := Vector2(-1, -1)          # 世界像素坐标


func setup(p_world: GdWorld) -> void:
	world = p_world
	sites = p_world.landing_sites
	_bake()


## 把整张世界烘成一张小图（群系颜色 + 巢穴淡化）
func _bake() -> void:
	var w := Cfg.WORLD_TILES
	image = Image.create(w, w, false, Image.FORMAT_RGBA8)
	var defs: Dictionary = DataLoader.new().table("tiles", "BIOME_DEF", {})
	var colors: Dictionary = {}
	for k in defs.keys():
		colors[int(k)] = Color(String((defs[k] as Dictionary).get("color", "#3a3a3a")))
	for y in w:
		for x in w:
			var b: int = int(world.biomes[y * w + x])
			var c: Color = colors.get(b, Color("#3a3a3a"))
			# 不可通行（岩石/水）压暗一点，方便一眼看出能降落的地方
			if world.is_blocked_px(float(x * Cfg.TILE) + 20.0, float(y * Cfg.TILE) + 20.0):
				c = c.darkened(0.35)
			image.set_pixel(x, y, c)
	tex = ImageTexture.create_from_image(image)


## 世界坐标 → 地图坐标（等比方块）
func world_to_map(p: Vector2, size: Vector2) -> Vector2:
	return p / float(Cfg.WORLD_PX) * size


func map_to_world(p: Vector2, size: Vector2) -> Vector2:
	return p / size * float(Cfg.WORLD_PX)


## 画到给定的 CanvasItem 上（size 是地图区边长）
func draw_map(c: CanvasItem, origin: Vector2, size: Vector2) -> void:
	if tex == null:
		return
	c.draw_texture_rect(tex, Rect2(origin, size), false)
	c.draw_rect(Rect2(origin, size), Color(0.55, 0.66, 0.78, 0.6), false, 2.0)
	var k := size / float(Cfg.WORLD_PX)
	# 巢穴：红点（越红越危险）
	for n in world.nests:
		if GdMath.truthy(n.get("destroyed", false)):
			continue
		var mp := origin + Vector2(float(n["x"]), float(n["y"])) * k
		c.draw_circle(mp, 3.0, Color(1.0, 0.31, 0.43, 0.85))
	# 废弃基地 / 地标：黄方块
	for poi in world.pois:
		var pp := origin + Vector2(float(poi["x"]), float(poi["y"])) * k
		c.draw_rect(Rect2(pp - Vector2(2, 2), Vector2(4, 4)), Color("#ffba4c"))
	# 推荐降落点
	for i in sites.size():
		var s: Dictionary = sites[i]
		var sp := origin + Vector2(float(s["x"]), float(s["y"])) * k
		var is_sel := i == selected
		c.draw_circle(sp, 9.0 if is_sel else 6.0,
			Color("#6ee7a8") if is_sel else Color(0.43, 0.9, 0.66, 0.55))
		c.draw_circle(sp, 2.5, Color("#0b0f16"))
