## 切图命令行入口
##
##   godot --headless --path . --script res://tests/slice_sheet.gd -- \
##     --sheet=<png> --cols=4 --rows=4 --out=<目录> --names=a,b,... [--bg=0.12] [--size=64] [--trim=0]
extends SceneTree


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i > 0:
			args[a.substr(2, i - 2)] = a.substr(i + 1)
	var sheet := String(args.get("sheet", ""))
	var out_dir := String(args.get("out", ""))
	var names: Array = String(args.get("names", "")).split(",")
	# 名字里允许用 @ 表示「用文件名前缀」之外的写法；这里只做去空格
	for i in names.size():
		names[i] = String(names[i]).strip_edges()
	var bg := float(args.get("bg", "0.12"))       # 去背景阈值（0 = 不去）
	var size := int(args.get("size", "64"))
	var grid := int(args.get("grid", "0"))        # >1 = 固定网格切（cols=rows=grid），见 slice_grid()
	var cols := int(args.get("cols", "0"))        # 非方阵网格（如 2x3 的巢穴表）
	var rows := int(args.get("rows", "0"))

	var res: Dictionary
	# ⚠️ 条件是「任一 > 1」而不是「两者都 > 1」：5×1 的单行素材表也是合法网格。
	# 第一版写成 and，结果 `--cols=5 --rows=1` 悄悄落回连通块模式，16 个图标只切出 1 张。
	if cols > 1 or rows > 1:
		res = SheetSlicer.slice_grid(sheet, out_dir, names, maxi(1, cols), maxi(1, rows), size)
	elif grid > 1:
		res = SheetSlicer.slice_grid(sheet, out_dir, names, grid, grid, size)
	else:
		res = SheetSlicer.slice(sheet, out_dir, names, bg, size)
	if not res.get("ok", false):
		print("SLICE_FAIL " + String(res.get("error", "?")))
		quit(1)
		return
	# boxes 一并打出来：切出来的每一块在源表上的坐标，是「第几行第几列」的**权威依据**
	# （靠肉眼比对源表容易张冠李戴 —— 上一版就是这么把 dronePlatform 和 forceField 弄反的）
	var boxes: Array = res.get("boxes", [])
	var brief: Array = []
	for b in boxes:
		brief.append([b.position.x, b.position.y, b.size.x * SheetSlicer.DOWNSCALE,
			b.size.y * SheetSlicer.DOWNSCALE])
	print("SLICE_OK " + JSON.stringify({
		"count": res["count"], "detected": res["detected"], "out": out_dir, "names": res["names"],
		"boxes": brief,
	}))
	quit(0)
