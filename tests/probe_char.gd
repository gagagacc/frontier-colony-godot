extends SceneTree
func _initialize() -> void:
	for id in ["engineer","pioneer","pilot","biologist"]:
		var t := Sprites.get_tex("char_" + id)
		print("PROBE char_%s → %s" % [id, "OK" if t != null else "null"])
	quit(0)
