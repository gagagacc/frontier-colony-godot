## 通用拼图（接触表）——把任意目录里的贴图按序号拼成一张，带序号角标。
##
##   godot --headless --path . --script res://tests/montage.gd -- \
##     --dir=assets/sprites --filter=tower_ --out=tools/shots/towers-montage.png [--cols=6] [--cell=112]
##
## 打印 `序号=文件名` 对照，配合图上的角标就能一眼看出「哪张画的是什么」。
extends SceneTree

const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"],
	"3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"],
	"7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "111"],
}


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i > 0:
			args[a.substr(2, i - 2)] = a.substr(i + 1)
	var dir := String(args.get("dir", "assets/sprites"))
	var filter := String(args.get("filter", ""))
	var out := String(args.get("out", "tools/shots/montage.png"))
	var cols := int(args.get("cols", "6"))
	var cell := int(args.get("cell", "112"))

	var files: Array = []
	for f in DirAccess.get_files_at(_abs(dir)):
		if not f.ends_with(".png"):
			continue
		if filter != "" and not f.begins_with(filter):
			continue
		files.append(f)
	files.sort()
	if files.is_empty():
		print("MONTAGE_FAIL 没找到贴图：" + dir + " 前缀=" + filter)
		quit(1)
		return

	var rows := int(ceil(float(files.size()) / float(cols)))
	var img := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.10, 0.13))
	for i in files.size():
		var src := Image.load_from_file(_abs(dir).path_join(files[i]))
		if src == null:
			continue
		src.convert(Image.FORMAT_RGBA8)
		var inner := cell - 10
		var keep := mini(src.get_width(), src.get_height())
		src.resize(inner, inner, Image.INTERPOLATE_NEAREST)
		var cx := (i % cols) * cell
		var cy := (i / cols) * cell
		# ⚠️ 这里必须 blend 缩放后的 src 本身：早先版本建了个空白 scaled 却 blend 它，拼图全黑
		img.blend_rect(src, Rect2i(0, 0, inner, inner), Vector2i(cx + 5, cy + 5))
		img.fill_rect(Rect2i(cx, cy, 24, 14), Color(0, 0, 0, 0.8))
		_draw_number(img, str(i), cx + 2, cy + 1)
		print("  %2d = %s (%dx%d)" % [i, files[i], keep, keep])
	DirAccess.make_dir_recursive_absolute(_abs(out).get_base_dir())
	img.save_png(_abs(out))
	print("MONTAGE_OK %s · %d 张 · %dx%d 网格" % [out, files.size(), cols, rows])
	quit(0)


## 相对路径 → 项目根下的绝对路径（绝对路径原样返回）
func _abs(p: String) -> String:
	if p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://" + p)


func _draw_number(img: Image, text: String, x: int, y: int) -> void:
	var col := Color(1, 1, 1)
	var cx := x
	for ch in text:
		var g: Array = GLYPHS.get(String(ch), [])
		for row in g.size():
			var line: String = g[row]
			for c in line.length():
				if line[c] == "1":
					for dy in 2:
						for dx in 2:
							img.set_pixel(cx + c * 2 + dx, y + row * 2 + dy, col)
		cx += 8
