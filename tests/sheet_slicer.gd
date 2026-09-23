## 精灵表切图器 —— 从一张生成素材表里切出多个独立 PNG。
##
##   godot --headless --path . --script res://tests/slice_sheet.gd -- \
##     --sheet=<png> --out=<目录> --names=a,b,c,... [--bg=0.13] [--size=64]
##
## ## 为什么不用「固定网格切」
##
## 第一版是按 cols×rows 均分切（1024/4=256 一格）。实测**切歪**：
## 生成模型给的 16 个图标虽然大致 4×4 排列，但**间距并不均匀**（每格内图标大小、
## 位置都有偏移），固定格子会把图标切成两半。所以改成**自动检测连通块**：
##
##   1. 去背景（把接近纯黑的像素变透明）
##   2. 在**降采样网格**上找连通块（1024² 逐像素跑并查集太慢，降到 256² 足够定位）
##   3. 把靠得近的块**合并**（一根炮管和它的底座是两块，得算一个图标）
##   4. 按「从上到下、从左到右」排序，依次取名字
##   5. 按合并后的包围盒裁剪 → 去边 → 统一缩放到 size×size
##
## 这样格子在哪儿、图标多大都不影响切图。
class_name SheetSlicer

const DOWNSCALE := 4          # 检测用降采样倍数
## 合并阈值（降采样坐标）。⚠️ 别调大：图标之间本来就有 10~15 个降采样像素的间隙，
## 阈值一大就会把相邻图标链式合并成一整块（第一版 =10 时 16 个图标合成 1 个）。
## 只要够把「炮管和它的底座」这种本来就挨着的两块连起来即可。
const MERGE_GAP := 2


static func slice(sheet_path: String, out_dir: String, names: Array,
	bg_threshold: float, out_size: int, pad: int = 4) -> Dictionary:
	if not FileAccess.file_exists(sheet_path):
		return { "ok": false, "error": "找不到素材表：" + sheet_path }
	var img := Image.load_from_file(sheet_path)
	if img == null:
		return { "ok": false, "error": "读不了这张图" }
	img.convert(Image.FORMAT_RGBA8)
	_remove_background(img, bg_threshold)

	var boxes := _find_boxes(img, pad)
	if boxes.is_empty():
		return { "ok": false, "error": "一个图标都没检测到（背景阈值可能不对）" }

	DirAccess.make_dir_recursive_absolute(out_dir)
	var made: Array = []
	for i in mini(boxes.size(), names.size()):
		var name := String(names[i]).strip_edges()
		if name == "" or name == "-":
			continue
		var box: Rect2i = boxes[i]
		var cell := img.get_region(box)
		var trimmed := _trim(cell)
		var out := _fit_square(trimmed, out_size)
		out.save_png(out_dir.path_join(name + ".png"))
		made.append(name)
	return { "ok": true, "count": made.size(), "names": made,
		"detected": boxes.size(), "boxes": boxes }


## 把接近背景色的像素变透明。像素素材常是纯黑底，所以按「暗 + 低饱和」判断，
## 而不是死抠某个颜色 —— 模型给的黑底往往不是纯 0。
static func _remove_background(img: Image, threshold: float) -> void:
	if threshold <= 0.0:
		return
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var mx := maxf(p.r, maxf(p.g, p.b))
			var mn := minf(p.r, minf(p.g, p.b))
			if mx <= threshold and (mx - mn) <= threshold * 0.7:
				img.set_pixel(x, y, Color(0, 0, 0, 0))


## 降采样 → 连通块 → 合并 → 排序 → 还原成全分辨率的包围盒
static func _find_boxes(img: Image, pad: int) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var dw := int(ceil(float(w) / DOWNSCALE))
	var dh := int(ceil(float(h) / DOWNSCALE))

	# ① 降采样：一小格内有任何不透明像素就算「实心」
	var solid := PackedByteArray()
	solid.resize(dw * dh)
	for dy in dh:
		for dx in dw:
			var hit := 0
			for oy in DOWNSCALE:
				for ox in DOWNSCALE:
					var x := dx * DOWNSCALE + ox
					var y := dy * DOWNSCALE + oy
					if x < w and y < h and img.get_pixel(x, y).a > 0.1:
						hit = 1
						break
				if hit == 1:
					break
			solid[dy * dw + dx] = hit

	# ② 连通块（4 邻域 BFS）
	var label := PackedInt32Array()
	label.resize(dw * dh)
	label.fill(-1)
	var boxes: Array = []
	for dy in dh:
		for dx in dw:
			if solid[dy * dw + dx] == 0 or label[dy * dw + dx] >= 0:
				continue
			var id := boxes.size()
			var x0 := dx
			var y0 := dy
			var x1 := dx
			var y1 := dy
			var queue: Array = [Vector2i(dx, dy)]
			label[dy * dw + dx] = id
			while not queue.is_empty():
				var p: Vector2i = queue.pop_back()
				x0 = mini(x0, p.x)
				y0 = mini(y0, p.y)
				x1 = maxi(x1, p.x)
				y1 = maxi(y1, p.y)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = p.x + (d as Vector2i).x
					var ny: int = p.y + (d as Vector2i).y
					if nx < 0 or ny < 0 or nx >= dw or ny >= dh:
						continue
					if solid[ny * dw + nx] == 0 or label[ny * dw + nx] >= 0:
						continue
					label[ny * dw + nx] = id
					queue.append(Vector2i(nx, ny))
			boxes.append(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))

	# ③ 合并靠得近的块（炮管 + 底座属于同一个图标）
	var merged := true
	while merged:
		merged = false
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				if _near(boxes[i], boxes[j], MERGE_GAP):
					boxes[i] = boxes[i].merge(boxes[j])
					boxes.remove_at(j)
					merged = true
					break
			if merged:
				break

	# ③.5 切开「被合并在一起的多个图标」
	#
	# 实测坑：MERGE_GAP 即便调到 2，仍有相邻图标被连成一块 ——
	# 最典型的是 sentry 那张切出来**两座塔**（一青一橙叠在一起）。
	# 处理办法：看包围盒内部有没有**整行/整列都是空的**，有就从那里切开。
	var split: Array = []
	for b in boxes:
		split.append_array(_split_on_gaps(solid, dw, b))
	boxes = split

	# ④ 去掉太小的噪点（< 0.4% 面积）
	var min_area := float(dw * dh) * 0.004
	var keep: Array = []
	for b in boxes:
		if float(b.size.x * b.size.y) >= min_area:
			keep.append(b)

	# ⑤ 排序：先按行分带（y 重叠的算同一行），行内从左到右
	keep.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		var ay := a.position.y + a.size.y / 2
		var by := b.position.y + b.size.y / 2
		var band := maxi(a.size.y, b.size.y) / 2
		if absi(ay - by) > band:
			return ay < by
		return a.position.x < b.position.x)

	# ⑥ 还原到全分辨率 + 留白
	var out: Array = []
	for b in keep:
		var x := maxi(0, b.position.x * DOWNSCALE - pad)
		var y := maxi(0, b.position.y * DOWNSCALE - pad)
		var x2 := mini(w, (b.position.x + b.size.x) * DOWNSCALE + pad)
		var y2 := mini(h, (b.position.y + b.size.y) * DOWNSCALE + pad)
		out.append(Rect2i(x, y, x2 - x, y2 - y))
	return out


static func _near(a: Rect2i, b: Rect2i, gap: int) -> bool:
	return not (a.position.x - gap > b.position.x + b.size.x
		or b.position.x - gap > a.position.x + a.size.x
		or a.position.y - gap > b.position.y + b.size.y
		or b.position.y - gap > a.position.y + a.size.y)


## 裁到不透明内容的包围盒
static func _trim(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.06:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < x0 or y1 < y0:
		return img
	return img.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))


## 按最长边等比缩放，居中放进正方形画布（像素风用最近邻）
static func _fit_square(img: Image, size: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var scale := float(size) / float(maxi(w, h))
	var nw := maxi(1, int(round(float(w) * scale)))
	var nh := maxi(1, int(round(float(h) * scale)))
	var scaled := Image.create(w, h, false, Image.FORMAT_RGBA8)
	scaled.blit_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
	scaled.resize(nw, nh, Image.INTERPOLATE_NEAREST)
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(scaled, Rect2i(0, 0, nw, nh), Vector2i((size - nw) / 2, (size - nh) / 2))
	return out


## 在空白行/列处把一个块切成多个（用于分开被误合并的相邻图标）
static func _split_on_gaps(solid: PackedByteArray, dw: int, b: Rect2i) -> Array:
	var x0 := b.position.x
	var y0 := b.position.y
	var x1 := b.position.x + b.size.x - 1
	var y1 := b.position.y + b.size.y - 1
	# 找「整行空」的位置
	var row_breaks: Array = []
	for y in range(y0, y1 + 1):
		var any := false
		for x in range(x0, x1 + 1):
			if solid[y * dw + x] == 1:
				any = true
				break
		if not any:
			row_breaks.append(y)
	var col_breaks: Array = []
	for x in range(x0, x1 + 1):
		var any := false
		for y in range(y0, y1 + 1):
			if solid[y * dw + x] == 1:
				any = true
				break
		if not any:
			col_breaks.append(x)
	if row_breaks.is_empty() and col_breaks.is_empty():
		return [b]      # 本来就是完整一块
	# 用空白行/列把范围切成若干子矩形（先按行切，再按列切）
	var out: Array = []
	var y_start := y0
	var y_edges: Array = row_breaks.duplicate()
	y_edges.append(y1 + 1)
	for ye in y_edges:
		if ye - 1 < y_start:
			continue
		var x_start := x0
		var x_edges: Array = []
		for xb in col_breaks:
			if xb >= x0 and xb <= x1:
				x_edges.append(xb)
		x_edges.append(x1 + 1)
		for xe in x_edges:
			if xe - 1 < x_start:
				continue
			var w: int = xe - x_start
			var h: int = ye - y_start
			if w > 0 and h > 0 and _has_content(solid, dw, x_start, y_start, w, h):
				out.append(Rect2i(x_start, y_start, w, h))
			x_start = xe + 1
		y_start = ye + 1
	return out if not out.is_empty() else [b]


static func _has_content(solid: PackedByteArray, dw: int, x: int, y: int, w: int, h: int) -> bool:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if solid[yy * dw + xx] == 1:
				return true
	return false