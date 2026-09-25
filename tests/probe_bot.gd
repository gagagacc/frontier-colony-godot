extends SceneTree
func _initialize() -> void:
	var b = LayaBot.new()
	print("PROBE LayaBot.new() → %s · enabled=%s" % [str(b != null), str(b.enabled)])
	b.free()
	quit(0)
