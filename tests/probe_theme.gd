## 诊断：主题里 Button / Panel 到底拿到了什么 StyleBox、贴图有没有真的加载
##
##   godot --headless --path . --script res://tests/probe_theme.gd
extends SceneTree


func _initialize() -> void:
	var th := UiTheme.build()
	for pair in [["Button", "normal"], ["Button", "hover"], ["Button", "pressed"],
			["Panel", "panel"], ["PanelContainer", "panel"], ["PopupPanel", "panel"]]:
		var type := String(pair[0])
		var item := String(pair[1])
		var sb := th.get_stylebox(item, type)
		if sb == null:
			print("PROBE %-16s %-8s = null（主题里没有 → 用引擎默认）" % [type, item])
			continue
		var line := "PROBE %-16s %-8s = %s" % [type, item, sb.get_class()]
		if sb is StyleBoxTexture:
			var sbt := sb as StyleBoxTexture
			var tex := sbt.texture
			line += " · 贴图 %s" % ("null（没加载到）" if tex == null else "%dx%d" % [tex.get_width(), tex.get_height()])
			line += " · 边距 L%.0f T%.0f R%.0f B%.0f" % [sbt.texture_margin_left,
				sbt.texture_margin_top, sbt.texture_margin_right, sbt.texture_margin_bottom]
			line += " · region %s" % str(sbt.region_rect)
		print(line)
	# 文件层再确认一遍
	for p in ["res://assets/ui/panel_bg.png", "res://assets/ui/button_bg.png", "res://assets/ui/bar_fill.png"]:
		var exists := ResourceLoader.exists(p)
		var size := "-"
		if exists:
			var t = load(p)
			if t is Texture2D:
				size = "%dx%d" % [t.get_width(), t.get_height()]
		print("FILE %-40s exists=%s size=%s" % [p, str(exists), size])

	# ③ 真实节点上的解析结果（这才是渲染时真正用的那条路）
	#
	# 光看 Theme 资源里有不算数：节点的主题解析要沿父链找到 Window，
	# 再按「节点自身 class → 各级父 class」查表。这里把节点真挂进树里问一遍。
	root.theme = th
	var pc := PanelContainer.new()
	var panel := Panel.new()
	var btn := Button.new()
	var lbl := Label.new()
	root.add_child(pc)
	root.add_child(panel)
	root.add_child(btn)
	root.add_child(lbl)
	for pair in [[pc, "panel"], [panel, "panel"], [btn, "normal"], [btn, "hover"]]:
		var node: Node = pair[0]
		var item := String(pair[1])
		var sb2 := (node as Control).get_theme_stylebox(item)
		var desc := "null（→ 引擎默认）"
		if sb2 != null:
			desc = sb2.get_class()
			if sb2 is StyleBoxTexture:
				var t2 := (sb2 as StyleBoxTexture).texture
				desc += " · 贴图 %s" % ("null" if t2 == null else "%dx%d" % [t2.get_width(), t2.get_height()])
		print("RUNTIME %-16s %-8s = %s" % [(node as Node).get_class(), item, desc])
	quit(0)
