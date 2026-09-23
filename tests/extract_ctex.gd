## 从 Godot 导入缓存 `.ctex` 里把原始贴图抠回来
##
##   godot --headless --path . --script res://tests/extract_ctex.gd -- \
##     --dir=.godot/imported --out=assets/sprites [--filter=tower_]
##
## ## 为什么需要这个
##
## 2026-09-23 重切素材表前用 `Remove-Item tower_*.png` 清了旧图，重切没跑出来，
## 于是 `assets/sprites/` 下只剩 `.import` 边车、PNG 本体全没了 —— 游戏里所有炮塔
## 退回 Kenney 通用贴图。
##
## 好在 Godot 导入过的贴图都进了 `.godot/imported/*.ctex`：
##   GST2 头（magic 4 + version 4 + w 4 + h 4 + ... ）之后，偏移 56 起是一段 **完整 WebP**（RIFF）。
## 所以直接抠 RIFF 块 → `Image.load_webp_from_buffer()` → 存 PNG，
## 拿回来的像素和当初被删的那张**逐像素一致**。
extends SceneTree


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i > 0:
			args[a.substr(2, i - 2)] = a.substr(i + 1)
	# ⚠️ 相对路径要手动 globalize：DirAccess 拿到相对路径不一定按项目根解析
	var dir := _abs(String(args.get("dir", ".godot/imported")))
	var out_dir := _abs(String(args.get("out", "assets/sprites")))
	var filter := String(args.get("filter", ""))
	DirAccess.make_dir_recursive_absolute(out_dir)

	var names := DirAccess.get_files_at(dir)
	if names.is_empty():
		print("EXTRACT_FAIL 目录为空或读不到：" + dir)
		quit(1)
		return

	var ok: Array = []
	var bad: Array = []
	for fn in names:
		if not fn.ends_with(".ctex"):
			continue
		if filter != "" and not fn.begins_with(filter):
			continue
		# tower_sentry.png-<md5>.ctex  →  tower_sentry.png
		var cut := fn.find(".png-")
		var base := fn if cut < 0 else fn.substr(0, cut + 4)
		var dst := out_dir.path_join(base)
		if FileAccess.file_exists(dst):
			bad.append(base + "（已存在，跳过）")
			continue
		var bytes := FileAccess.get_file_as_bytes(dir.path_join(fn))
		var off := _find_riff(bytes)
		if off < 0:
			bad.append(base + "（没找到 RIFF）")
			continue
		if off + 8 > bytes.size():
			bad.append(base + "（RIFF 头越界）")
			continue
		var riff_len := bytes.decode_u32(off + 4) + 8      # RIFF 声明长度 + "RIFF"/长度 自身 8 字节
		var end := mini(bytes.size(), off + riff_len)
		var webp := bytes.slice(off, end)
		var img := Image.new()
		if img.load_webp_from_buffer(webp) != OK:
			bad.append(base + "（WebP 解码失败）")
			continue
		if img.save_png(dst) != OK:
			bad.append(base + "（存 PNG 失败）")
			continue
		ok.append("%s  %dx%d" % [base, img.get_width(), img.get_height()])

	print("EXTRACT_OK 还原 %d 张 → %s" % [ok.size(), out_dir])
	for s in ok:
		print("  ✓ " + s)
	for s in bad:
		print("  × " + s)
	quit(0 if ok.size() > 0 else 1)


## 在字节流里找 RIFF....WEBP 签名（.ctex 里是 WebP 载荷）
func _find_riff(b: PackedByteArray) -> int:
	for i in range(0, maxi(0, b.size() - 12)):
		if b[i] == 0x52 and b[i + 1] == 0x49 and b[i + 2] == 0x46 and b[i + 3] == 0x46 \
			and b[i + 8] == 0x57 and b[i + 9] == 0x45 and b[i + 10] == 0x42 and b[i + 11] == 0x50:
			return i
	return -1


## 相对路径 → 项目根下的绝对路径
func _abs(p: String) -> String:
	if p.begins_with("res://") or p.is_absolute_path():
		return ProjectSettings.globalize_path(p) if p.begins_with("res://") else p
	return ProjectSettings.globalize_path("res://" + p)
