extends SceneTree
func _initialize() -> void:
	var ok := 0
	var bad: Array = []
	for k in ["grub","crawler","shellback","nestDevourer","voidSiren"]:
		for v in ["s","d","f"]:
			var t := Sprites.get_tex("enemy_%s_%s" % [k, v])
			if t != null: ok += 1
			else: bad.append("enemy_%s_%s" % [k, v])
	print("VIEWS ok=%d bad=%s" % [ok, ",".join(bad) if bad.size() > 0 else "无"])
	quit(0)
