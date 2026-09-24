## 地形层 —— `renderer.drawTerrain` / `renderChunk` / `drawSolidEdge` 的移植。
##
## JS 版是「每个区块烘一张 canvas，再整张贴上去」；Godot 这边不需要那么做：
## 所有地块都来自**同一张图集**，Godot 会把同材质的 draw_texture_rect_region
## 合批成极少的 draw call，直接逐格画反而更快、也不需要维护区块缓存
##（也就不会再踩「缓存键没带世界 id」那个坑）。
##
## 「看得见的崖边」照搬 JS 的规则：实心地块只要挨着可通行地块，
## 就在交界处画一条亮边 —— 玩家反馈过「同样的材质看着能走，撞上去却是空气墙」。
extends Node2D

const TILE_PX := Cfg.TILE
const EDGE_COLOR := Color(1.0, 0.925, 0.745, 0.34)

var world: GdWorld
var atlas: TileAtlas
var camera: Camera2D
var show_flow := false
var flow: FlowField

## 统计（用来观察合批效果与可见格数）
var visible_tiles := 0
var drawn_edges := 0


func setup(p_world: GdWorld, p_atlas: TileAtlas, p_camera: Camera2D) -> void:
	world = p_world
	atlas = p_atlas
	camera = p_camera
	queue_redraw()


## 每帧重画。
##
## CanvasItem 的 `_draw` 只在被要求时执行 —— 相机跟随移动、或者换了一整个
## World（进副本）时都必须重画。以前只在 setup 时画一次，结果是：
## 进副本后画面停在**清屏色**上（玩家传送到了地图另一处，旧画面在视野外，
## 而新画面从来没画过）。地表上因为开局画过一次、视角没离开那块区域，
## 所以一直没暴露。
func _process(_dt: float) -> void:
	queue_redraw()


## 水面波光材质（在 _ready 里挂上；加载失败就退回无材质）
var shimmer_material: ShaderMaterial = null


func _ready() -> void:
	var path := "res://scripts/render/water_shimmer.gdshader"
	if ResourceLoader.exists(path):
		var sh := load(path)
		if sh is Shader:
			shimmer_material = ShaderMaterial.new()
			shimmer_material.shader = sh
			material = shimmer_material


func _draw() -> void:
	if world == null or atlas == null or atlas.texture == null:
		return
	var view := _view_rect()
	var tx0 := maxi(0, int(floor(view.position.x / TILE_PX)) - 1)
	var ty0 := maxi(0, int(floor(view.position.y / TILE_PX)) - 1)
	var tx1 := mini(Cfg.WORLD_TILES - 1, int(ceil(view.end.x / TILE_PX)) + 1)
	var ty1 := mini(Cfg.WORLD_TILES - 1, int(ceil(view.end.y / TILE_PX)) + 1)

	visible_tiles = 0
	drawn_edges = 0
	for ty in range(ty0, ty1 + 1):
		for tx in range(tx0, tx1 + 1):
			var idx := ty * Cfg.WORLD_TILES + tx
			var tile: int = world.tiles[idx]
			var region := atlas.region_for(tile, world.variant[idx])
			draw_texture_rect_region(atlas.texture,
				Rect2(float(tx * TILE_PX), float(ty * TILE_PX), float(TILE_PX), float(TILE_PX)),
				region)
			visible_tiles += 1
			# 实心地块的崖边
			if Cfg.is_solid_tile(tile):
				_draw_solid_edges(tx, ty)
	# 材质交界的过渡带（草地→沙地这种）——画在地块之上、崖边描边之下
	if show_blend:
		_draw_blend_pass(tx0, ty0, tx1, ty1)
	# 巢壁沿通道描边（副本里靠它分辨「哪里能走」）
	for ty in range(ty0, ty1 + 1):
		for tx in range(tx0, tx1 + 1):
			if world.tiles[ty * Cfg.WORLD_TILES + tx] == Cfg.T_NEST_WALL:
				_draw_nest_edges(tx, ty)
	# 流场箭头（按 F 切换）
	if show_flow and flow != null:
		_draw_flow()


## 材质交界的**过渡带** —— 把邻格材质往本格"侵入"半格，边缘用顶点 alpha 渐变 + 噪声抖动。
##
## ## 为什么不用 autotile 拼块
##
## 正经的 47 块 autotile（blob tileset）× 6 种材质 = 282 张素材，生图根本产不出来；
## 而这里只需要**把同一种材质多画半格**：靠边处不透明度高、往内渐隐，再把内侧边界按
## 两条不同频率的正弦抖一抖，视觉上就是自然的犬牙交错。
## 纯代码、零素材，以后加新地表材质自动适用。
##
## ## ⚠️ 性能：必须批量合并
##
## 这块地形是**碎 mosaic**（大量单格异材质），实测「每块边界一次 draw_polygon」会把帧率
## 从 170 打到 14 —— 一帧两千多次绘制调用。改成**按图集区域分桶**、同一档位合并成一次
## `draw_polygon`，并且把分段数压到 4 段。
##
## 只在「两边都是可走地表」时混合：崖边（实心）另有描边，混上去反而糊。
const BLEND_SEGMENTS := 4          # 每条边分几段（4 段 = 每带 10 个顶点）
const BLEND_ALPHA := 0.8           # 侵入侧的最大不透明度（别到 1，留点透色更像混合）
const BLEND_REACH := 0.68          # 最大侵入深度（格宽的倍数，越大越"融化"）
const BLEND_MIN_MASS := 1          # 邻居里至少几个同材质才算「成片」（1 = 只要有伴就过渡）

var show_blend := true

## 抖动查表：省掉每帧几万次 sin()。
## 抖动只跟「沿边坐标 + 位置种子」有关，精度 1/64 格完全够用（亚像素级差异看不出来）。
const WOBBLE_N := 64
static var _wobble_lut: PackedFloat32Array = PackedFloat32Array()


static func _wobble_table() -> PackedFloat32Array:
	if _wobble_lut.size() == WOBBLE_N:
		return _wobble_lut
	_wobble_lut.resize(WOBBLE_N)
	for i in WOBBLE_N:
		var a := float(i) / float(WOBBLE_N) * TAU
		# 两条正弦叠加：低频决定大块形状，高频加毛刺（提前算好存表）
		_wobble_lut[i] = 0.55 + 0.45 * (0.5 + 0.5 * sin(a)) * (0.6 + 0.4 * sin(a * 3.3))
	return _wobble_lut


## 这块地是不是「成片的」（至少两个正交邻居同材质）。
##
## ⚠️ 这条判断是性能与观感的双赢：这块地形是碎 mosaic，大量单格异材质斑点，
## 给斑点做过渡又贵又糊；只给成片区域做，帧率回来了，斑点保持锐利反而更清楚。
func _is_mass(tx: int, ty: int, tile: int) -> bool:
	var n := 0
	if tx > 0 and world.tiles[ty * Cfg.WORLD_TILES + tx - 1] == tile:
		n += 1
	if tx < Cfg.WORLD_TILES - 1 and world.tiles[ty * Cfg.WORLD_TILES + tx + 1] == tile:
		n += 1
	if ty > 0 and world.tiles[(ty - 1) * Cfg.WORLD_TILES + tx] == tile:
		n += 1
	if ty < Cfg.WORLD_TILES - 1 and world.tiles[(ty + 1) * Cfg.WORLD_TILES + tx] == tile:
		n += 1
	return n >= BLEND_MIN_MASS


## 一趟把所有过渡带收进分桶，再按桶各画一次
##
## ## ⚠️ 性能：几何必须**按区块烘焙缓存**
##
## 实测数据（同一块碎 mosaic 地形）：
##   · 每帧现算、每带一次 draw_polygon → **14 FPS**（两千多次绘制调用）
##   · 改成按图集区域分桶批量画        → **25 FPS**
##   · 再加「只给成片材质做、抖动查表」→ **89 FPS**（但单格斑点没有过渡，还是硬边）
##   · 放宽到「只要有伴就过渡」        → **33 FPS**（现算太贵）
##
## 过渡带几何只跟 **tiles** 有关，跟相机无关 —— 所以按区块烘一次、反复用；
## tiles 变了（挖副本、改地形）靠 `world.tile_revision` 整体失效重烘。
## 这样既能把过渡做足，又不用每帧重算。
const BLEND_CACHE_LIMIT := 128

var _blend_cache: Dictionary = {}      # "cx,cy" -> { rev:int, batches: Dictionary }
var _blend_order: Array = []           # 简单 LRU（先进先出淘汰）


func _draw_blend_pass(tx0: int, ty0: int, tx1: int, ty1: int) -> void:
	var c0x := tx0 / Cfg.CHUNK
	var c0y := ty0 / Cfg.CHUNK
	var c1x := tx1 / Cfg.CHUNK
	var c1y := ty1 / Cfg.CHUNK
	for cy in range(c0y, c1y + 1):
		for cx in range(c0x, c1x + 1):
			var batches := _chunk_blend(cx, cy)
			for key in batches.keys():
				var b: Dictionary = batches[key]
				var pts: PackedVector2Array = b["pts"]
				if pts.size() >= 3:
					draw_polygon(pts, b["cols"], b["uvs"], atlas.texture)


## 取某区块的过渡带几何（缓存未命中就烘一份）
func _chunk_blend(cx: int, cy: int) -> Dictionary:
	var key := "%d,%d" % [cx, cy]
	if _blend_cache.has(key):
		var rec: Dictionary = _blend_cache[key]
		if int(rec["rev"]) == world.tile_revision:
			return rec["batches"]
		_blend_cache.erase(key)
	var buckets: Dictionary = {}
	var x0 := cx * Cfg.CHUNK
	var y0 := cy * Cfg.CHUNK
	var x1 := mini(Cfg.WORLD_TILES - 1, x0 + Cfg.CHUNK - 1)
	var y1 := mini(Cfg.WORLD_TILES - 1, y0 + Cfg.CHUNK - 1)
	if x0 >= Cfg.WORLD_TILES or y0 >= Cfg.WORLD_TILES:
		return buckets
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			_collect_blend(buckets, tx, ty, Vector2i(1, 0))
			_collect_blend(buckets, tx, ty, Vector2i(-1, 0))
			_collect_blend(buckets, tx, ty, Vector2i(0, 1))
			_collect_blend(buckets, tx, ty, Vector2i(0, -1))
	_blend_cache[key] = { "rev": world.tile_revision, "batches": buckets }
	_blend_order.append(key)
	while _blend_order.size() > BLEND_CACHE_LIMIT:
		var old: String = _blend_order.pop_front()
		_blend_cache.erase(old)
	return buckets


func _collect_blend(buckets: Dictionary, tx: int, ty: int, dir: Vector2i) -> void:
	var nx := tx + dir.x
	var ny := ty + dir.y
	if nx < 0 or ny < 0 or nx >= Cfg.WORLD_TILES or ny >= Cfg.WORLD_TILES:
		return
	var idx := ty * Cfg.WORLD_TILES + tx
	var nidx := ny * Cfg.WORLD_TILES + nx
	var tile: int = world.tiles[idx]
	var ntile: int = world.tiles[nidx]
	if ntile == tile:
		return
	if Cfg.is_solid_tile(tile) or Cfg.is_solid_tile(ntile):
		return
	# 只在两边都是「成片材质」时做过渡（单格斑点不混，见 _is_mass 注释）
	if not _is_mass(tx, ty, tile) or not _is_mass(nx, ny, ntile):
		return
	var region := atlas.region_for(ntile, world.variant[nidx])
	var tx0 := float(tx * TILE_PX)
	var ty0 := float(ty * TILE_PX)
	var horizontal := dir.x != 0
	var edge: float = 0.0
	if horizontal:
		edge = tx0 + float(TILE_PX) if dir.x > 0 else tx0
	else:
		edge = ty0 + float(TILE_PX) if dir.y > 0 else ty0
	var inward := -1.0 if (dir.x > 0 or dir.y > 0) else 1.0
	var seedv := float((tx * 73856093) ^ (ty * 19349663)) * 0.00013
	var lut := _wobble_table()
	# 分桶键 = 图集区域左上角（同材质同明暗档才可能合并）
	var key := "%d,%d" % [int(region.position.x), int(region.position.y)]
	if not buckets.has(key):
		buckets[key] = { "pts": PackedVector2Array(), "cols": PackedColorArray(),
			"uvs": PackedVector2Array() }
	var b: Dictionary = buckets[key]
	var pts: PackedVector2Array = b["pts"]
	var cols: PackedColorArray = b["cols"]
	var uvs: PackedVector2Array = b["uvs"]
	for i in BLEND_SEGMENTS + 1:
		var t := float(i) / float(BLEND_SEGMENTS)
		var along := lerpf(ty0, ty0 + float(TILE_PX), t) if horizontal \
			else lerpf(tx0, tx0 + float(TILE_PX), t)
		var li := int(fposmod(along * 0.16 + seedv * 900.0, 1.0) * float(WOBBLE_N)) % WOBBLE_N
		var reach := float(TILE_PX) * BLEND_REACH * lut[li]
		var bp := Vector2(edge, along) if horizontal else Vector2(along, edge)
		var ip := Vector2(edge + inward * reach, along) if horizontal \
			else Vector2(along, edge + inward * reach)
		pts.append(bp)
		cols.append(Color(1, 1, 1, BLEND_ALPHA))
		uvs.append(_blend_uv(region, bp, edge, tx0, ty0, horizontal))
		pts.append(ip)
		cols.append(Color(1, 1, 1, 0.0))
		uvs.append(_blend_uv(region, ip, edge, tx0, ty0, horizontal))


## 过渡带取样：把**邻格那张贴图**沿侵入方向延长出去（边界处取到贴图边缘，往内退一整格）
func _blend_uv(region: Rect2, p: Vector2, edge: float, tx0: float, ty0: float,
	horizontal: bool) -> Vector2:
	if horizontal:
		var u := region.position.x + ((p.x - edge) / float(TILE_PX) + 1.0) * region.size.x
		var v := region.position.y + ((p.y - ty0) / float(TILE_PX)) * region.size.y
		return Vector2(u, v)
	var u2 := region.position.x + ((p.x - tx0) / float(TILE_PX)) * region.size.x
	var v2 := region.position.y + ((p.y - edge) / float(TILE_PX) + 1.0) * region.size.y
	return Vector2(u2, v2)


func _draw_flow() -> void:
	var step := 6
	var t := float(TILE_PX * flow.cell)
	for gy in range(0, flow.h, step):
		for gx in range(0, flow.w, step):
			var idx := gy * flow.w + gx
			if flow.stamp[idx] != flow.generation:
				continue
			var dx := flow.dir_x[idx]
			var dy := flow.dir_y[idx]
			if absf(dx) < 0.01 and absf(dy) < 0.01:
				continue
			var base := Vector2((float(gx) + 0.5) * t, (float(gy) + 0.5) * t)
			draw_line(base, base + Vector2(dx, dy) * 22.0, Color(0.5, 1.0, 0.7, 0.5), 2.0)


func _view_rect() -> Rect2:
	if camera == null:
		return Rect2(0, 0, 1280, 720)
	var size := get_viewport_rect().size / camera.zoom
	var center := camera.global_position
	return Rect2(center - size / 2.0, size)


func _walkable_at(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= Cfg.WORLD_TILES or ty >= Cfg.WORLD_TILES:
		return false
	return not Cfg.is_solid_tile(world.tiles[ty * Cfg.WORLD_TILES + tx])


func _draw_solid_edges(tx: int, ty: int) -> void:
	var px := float(tx * TILE_PX)
	var py := float(ty * TILE_PX)
	var t := float(TILE_PX)
	if _walkable_at(tx, ty + 1):
		draw_line(Vector2(px, py + t), Vector2(px + t, py + t), EDGE_COLOR, 2.0)
	if _walkable_at(tx, ty - 1):
		draw_line(Vector2(px, py), Vector2(px + t, py), EDGE_COLOR, 2.0)
	if _walkable_at(tx + 1, ty):
		draw_line(Vector2(px + t, py), Vector2(px + t, py + t), EDGE_COLOR, 2.0)
	if _walkable_at(tx - 1, ty):
		draw_line(Vector2(px, py), Vector2(px, py + t), EDGE_COLOR, 2.0)
	drawn_edges += 1


func _nest_open_at(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= Cfg.WORLD_TILES or ty >= Cfg.WORLD_TILES:
		return false
	var t: int = world.tiles[ty * Cfg.WORLD_TILES + tx]
	return t == Cfg.T_NEST_FLOOR or t == Cfg.T_NEST_ORGAN


func _draw_nest_edges(tx: int, ty: int) -> void:
	var px := float(tx * TILE_PX)
	var py := float(ty * TILE_PX)
	var t := float(TILE_PX)
	var c := Color(1.0, 0.275, 0.392, 0.20)
	if _nest_open_at(tx, ty + 1):
		draw_line(Vector2(px, py + t), Vector2(px + t, py + t), c, 2.0)
	if _nest_open_at(tx, ty - 1):
		draw_line(Vector2(px, py), Vector2(px + t, py), c, 2.0)
	if _nest_open_at(tx + 1, ty):
		draw_line(Vector2(px + t, py), Vector2(px + t, py + t), c, 2.0)
	if _nest_open_at(tx - 1, ty):
		draw_line(Vector2(px, py), Vector2(px, py + t), c, 2.0)


## 崖边签名：给黄金对比用（把「哪几面该描边」编码成一个整数哈希）
func solid_edge_signature() -> int:
	var h := 2166136261
	for ty in Cfg.WORLD_TILES:
		for tx in Cfg.WORLD_TILES:
			var idx := ty * Cfg.WORLD_TILES + tx
			if not Cfg.is_solid_tile(world.tiles[idx]):
				continue
			var mask := 0
			if _walkable_at(tx, ty + 1):
				mask |= 1
			if _walkable_at(tx, ty - 1):
				mask |= 2
			if _walkable_at(tx + 1, ty):
				mask |= 4
			if _walkable_at(tx - 1, ty):
				mask |= 8
			if mask != 0:
				h = GdMath.imul(h ^ (idx * 16 + mask), 16777619)
	return h & GdMath.U32
