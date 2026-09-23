## 地形绘制成本探针 —— 决定「要不要换成 TileMapLayer」用数据说话。
##
##   godot --headless --path . --script res://tests/probe_terrain.gd
##
## 现在的地形是**逐格** `draw_texture_rect_region`（1280×720 视口约 630 格），
## 每格还要 `atlas.region_for()` 查一次区域。这里把这两件事的 CPU 成本量出来：
##   - 如果每帧只有零点几毫秒 → 换 TileMapLayer 收益有限（但它仍能省掉 GDScript 循环）
##   - 如果到毫秒级 → 值得换
extends SceneTree


func _initialize() -> void:
	var world := GdWorld.new("terrain-probe", {})
	var atlas := TileAtlas.new()
	atlas.build(DataLoader.new().table("tiles", "TILE_DEF", {}))
	# 视口约 1280×720 → 32×18 格（TILE_PX=40）
	var cols := 33
	var rows := 19
	var frames := 240

	var t0 := Time.get_ticks_usec()
	var acc := 0
	for f in frames:
		for ty in rows:
			for tx in cols:
				var idx := (ty + 3) * Cfg.WORLD_TILES + (tx + 5)
				var tile: int = world.tiles[idx]
				var region := atlas.region_for(tile, world.variant[idx])
				# 模拟一次 draw_texture_rect_region 的参数准备（真正绘制在 GPU 上）
				acc += int(region.position.x) + int(region.position.y)
	var us := float(Time.get_ticks_usec() - t0) / float(frames)
	print("TERRAIN_PROBE " + JSON.stringify({
		"tiles_per_frame": cols * rows,
		"ms_per_frame": snappedf(us / 1000.0, 0.001),
		"frames": frames,
		"checksum": acc,
	}))
	print("每帧 %.3f ms（%d 格）" % [us / 1000.0, cols * rows])
	quit(0)
