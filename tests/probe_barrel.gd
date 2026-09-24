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

## 「没有炮管」判据：最远点半径 / 等效半径 **低于**这个值才算纯圆盘（渲染时不旋转）。
##
## ⚠️ 实测这批俯视素材全部落在 **1.9~2.4** —— 圆底座 + 炮管/桅杆/旋翼都会把最远点推远，
##    所以判据**基本不会触发**，11 座塔一律按量出的仰角旋转。
##
## 保留这个机制的两个理由：
##   ① 以后真画出纯圆盘素材（比如地雷、力场核心）时不用改代码；
##   ② 渲染端「-1 = 不旋转」的约定有个明确出处。
##
## 顺带一提：力场穹顶 / 无人机平台这类**旋转对称**的美术，转与不转看起来一样，
## 按仰角转过去也不亏 —— 所以这里不需要为它们做特判。
const ROUND_RATIO := 1.15


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
		# 「有没有炮管」的**本质判据**：最远点半径 / 等效半径。
		#
		# ⚠️ 别再用镜像 IoU 判对称：换成俯视图之后圆底座让所有塔的 IoU 都涨到 0.90+，
		#    cryo / 火焰塔被误判成「没有炮管 → 不旋转」——正是玩家抱怨的 bug 反过来。
		#    圆盘：最远点≈等效半径（比值≈1.0）；圆盘 + 一根炮管：比值 1.6 以上。
		var area := 0
		var rmax := 0.0
		for y in h:
			for x in w:
				if img.get_pixel(x, y).a > 0.15:
					area += 1
					var dd := Vector2(float(x) - bx, float(y) - by).length()
					if dd > rmax:
						rmax = dd
		var r_eq := sqrt(float(area) / PI) if area > 0 else 1.0
		var ratio := rmax / maxf(1.0, r_eq)
		var symmetric := ratio < ROUND_RATIO
		if symmetric:
			table[key] = -1.0
		else:
			table[key] = snappedf(absf(deg_to_rad(ang)), 0.0001)
			angles.append(absf(ang))
		print("%-24s (%6.1f,%3d)  (%6.1f,%6.1f)  %7.1f  IoU %5.3f  最远/等效 %5.2f%s" % [
			f, muzzle_x, min_y, bx, by, ang, iou, ratio,
			"  ← 无炮管（圆盘），不旋转" if symmetric else ""])
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
