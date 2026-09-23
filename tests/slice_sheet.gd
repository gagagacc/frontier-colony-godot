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

	var res: Dictionary = SheetSlicer.slice(sheet, out_dir, names, bg, size)
	if not res.get("ok", false):
		print("SLICE_FAIL " + String(res.get("error", "?")))
		quit(1)
		return
	print("SLICE_OK " + JSON.stringify({
		"count": res["count"], "detected": res["detected"], "out": out_dir, "names": res["names"],
	}))
	quit(0)
