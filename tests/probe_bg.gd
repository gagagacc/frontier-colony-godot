extends SceneTree
func _initialize() -> void:
	for n in ["ui_bg_title","ui_bg_planet","ui_bg_character","ui_bg_settings"]:
		var t := Sprites.get_tex(n)
		print("PROBE %s → %s" % [n, "OK %dx%d" % [t.get_width(), t.get_height()] if t != null else "null"])
	quit(0)
