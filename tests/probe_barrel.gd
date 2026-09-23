## 量炮塔贴图里**炮管的实际朝向**，生成 `data/barrel_angles.json`（渲染旋转补偿的标定表）
##
##   godot --headless --path . --script res://tests/probe_barrel.gd -- [--dir=assets/sprites] [--write=1]
##
## ## 为什么需要它
##
## 贴图是「炮管指向右上」的斜视图，画到场上要按瞄准角旋转。旋转补偿必须等于**贴图里炮管的仰角**，
## 否则炮管和目标差一个固定夹角 —— 用户报的「炮管和打击方向不一致」就是这个问题。
##
## 而 11 张生成素材的仰角**各不相同**（实测 59.7°~69.9°），写死的单一常量必然有几座塔是歪的。
## 所以这里逐张量、写进 JSON，渲染时按塔查表。
##
## ## 算法
##
##   · 炮口 = 不透明像素里 **y 最小**的那个（炮管朝上，最高点就是炮口；同一行取 x 平均）
##   · 回转中心 ≈ 贴图**底部 25% 高度**内不透明像素的重心（底座在那儿）
##   · 仰角 = atan2(炮口 - 回转中心)，Godot 的 y 向下，所以右上 = 负角；取正值存表
##   · **镜像对称度**（左右翻转后的 IoU）≥ 0.88 判为「没有炮管」的对称贴图（力场穹顶、无人机平台），
##     存 -1，渲染时**不旋转** —— 否则穹顶会跟着目标乱转，看着像在飘
extends SceneTree

const OUT_PATH := "res://data/barrel_angles.json"
const SYMMETRIC_IOU := 0.88


func _initialize() -> void:
	var dir := "assets/sprites"
	var filter := "tower_"
	var write := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
		elif a.begins_with("--filter="):
			filter = a.substr(9)
		elif a.begins_with("--write="):
			write = a.substr(8) == "1"
	_run(dir, filter, write)


func _run(dir: String, filter: String, write: bool) -> void:
	var base := ProjectSettings.globalize_path("res://" + dir)
	var files := DirAccess.get_files_at(base)
	files.sort()
	var table := {}
	var angles: Array = []
	print("贴图                     炮口(x,y)      底座重心(x,y)   仰角°   镜像IoU")
	for f in files:
		if not f.ends_with(".png") or not f.begins_with(filter):
			continue
		var key := f.get_basename()
		# Kenney 备用件是「零件」不是整塔，不参与标定
		if key == "tower_light" or key == "tower_heavy":
			continue
		var img := Image.load_from_file(base.path_join(f))
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var y0 := h
		var y1 := -1
		for y in h:
			for x in w:
				if img.get_pixel(x, y).a > 0.15:
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
		if y1 < y0:
			continue
		# 回转中心 = 底部 25% 的重心
		var base_top := y0 + int(float(y1 - y0) * 0.75)
		var bx := 0.0
		var by := 0.0
		var bn := 0
		for y in range(base_top, y1 + 1):
			for x in w:
				if img.get_pixel(x, y).a > 0.15:
					bx += float(x)
					by += float(y)
					bn += 1
		# 炮口 = 最上面一行不透明像素
		var min_y := h
		var muzzle_x := 0.0
		var muzzle_n := 0
		for y in h:
			var sx := 0.0
			var hit := 0
			for x in w:
				if img.get_pixel(x, y).a > 0.15:
					sx += float(x)
					hit += 1
			if hit > 0:
				min_y = y
				muzzle_x = sx / float(hit)
				muzzle_n = hit
				break
		if bn == 0 or muzzle_n == 0:
			continue
		bx /= float(bn)
		by /= float(bn)
		var ang := rad_to_deg(atan2(float(min_y) - by, muzzle_x - bx))
		# 镜像对称度
		var diff := 0
		var total := 0
		for y in h:
			for x in w / 2:
				var l := img.get_pixel(x, y).a > 0.15
				var r := img.get_pixel(w - 1 - x, y).a > 0.15
				if l or r:
					total += 1
				if l != r:
					diff += 1
		var iou := 1.0 if total == 0 else 1.0 - float(diff) / float(total)
		var symmetric := iou >= SYMMETRIC_IOU
		if symmetric:
			table[key] = -1.0
		else:
			table[key] = snappedf(absf(deg_to_rad(ang)), 0.0001)
			angles.append(absf(ang))
		print("%-24s (%6.1f,%3d)  (%6.1f,%6.1f)  %7.1f  %6.3f%s" % [
			f, muzzle_x, min_y, bx, by, ang, iou, "  ← 对称，不旋转" if symmetric else ""])
	print("BARREL_PROBE " + JSON.stringify({ "n": table.size(), "barrels": angles.size(), "table": table }))
	if write:
		var f2 := FileAccess.open(ProjectSettings.globalize_path(OUT_PATH), FileAccess.WRITE)
		if f2 == null:
			print("BARREL_FAIL 写不了 " + OUT_PATH)
			quit(1)
			return
		f2.store_string(JSON.stringify(table, "  ") + "\n")
		f2.close()
		print("BARREL_WROTE " + OUT_PATH + " （" + str(table.size()) + " 条）")
	quit(0)
