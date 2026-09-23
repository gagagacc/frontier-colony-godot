## 素材表诊断：看背景到底有多亮、阈值该定多少
##
##   godot --headless --path . --script res://tests/probe_sheet.gd -- --sheet=<png>
extends SceneTree


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i > 0:
			args[a.substr(2, i - 2)] = a.substr(i + 1)
	var path := String(args.get("sheet", ""))
	var img := Image.load_from_file(path)
	if img == null:
		print("PROBE_FAIL 读不了 " + path)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	# 背景亮度分布：统计不同亮度档的像素数
	var bins := PackedInt32Array()
	bins.resize(10)
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var p := img.get_pixel(x, y)
			var mx := maxf(p.r, maxf(p.g, p.b))
			bins[clampi(int(mx * 10.0), 0, 9)] += 1
	var total := 0
	for b in bins:
		total += b
	var out := {}
	var acc := 0
	for i in 10:
		acc += bins[i]
		out["<%.1f" % (float(i + 1) / 10.0)] = "%d%%" % int(round(float(acc) / float(maxi(1, total)) * 100.0))
	var corner := img.get_pixel(4, 4)
	print("PROBE " + JSON.stringify({
		"size": "%dx%d" % [w, h],
		"corner": "%.3f,%.3f,%.3f" % [corner.r, corner.g, corner.b],
		"cumulative": out,
	}))
	quit(0)
