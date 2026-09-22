## 音频 —— Godot 的音频总线 + 池化播放器。
##
## 这是审计出来的**最大空白**：JS 侧有 122 处音效/音乐调用，Godot 侧几乎是静音的。
## 引擎优势在于：
##   1. **音频总线**：SFX / BGM 各一条，音量设置直接作用在总线上（不必逐个播放器调）；
##   2. **播放器池**：同一个音效连响时不会互相打断（JS 的 WebAudio 也得自己管）；
##   3. **变体随机 + 音高微抖**：同一动作听起来不机械。
##
## 素材：Kenney 的 CC0 音效包（impact / interface / sci-fi），已拷进 `assets/audio/`。
class_name Audio

## 逻辑名 → 变体文件（多个变体随机取一个）
const BANK := {
	"shoot_light": ["shoot_light_0", "shoot_light_1"],
	"shoot_heavy": ["shoot_heavy_0", "shoot_heavy_1"],
	"hit": ["hit_0", "hit_1", "hit_2"],
	"explode": ["explode_0", "explode_1"],
	"unlock": ["unlock_0"],
	"build": ["build_0"],
	"error": ["error_0"],
	"base_hit": ["base_hit_0"],
	"step": ["step_0", "step_1", "step_2", "step_3"],
}

const POOL_SIZE := 12

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}          # 逻辑名 -> [AudioStream...]
var _next := 0
var _rng := Rng.new("audio")
var enabled := true
var sfx_volume := 1.0


func setup(host: Node) -> void:
	# SFX 总线（音量设置作用在它上面；没有就退回 Master）
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		host.add_child(p)
		_players.append(p)
	# 载入变体
	for name in BANK.keys():
		var list: Array = []
		for f in BANK[name]:
			var path := "res://assets/audio/%s.ogg" % f
			if ResourceLoader.exists(path):
				var s := load(path)
				if s is AudioStream:
					list.append(s)
		if not list.is_empty():
			_streams[name] = list


## 播一个音效。`volume_db` 用于按距离/重要度调音量。
func play(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if not enabled or not _streams.has(name):
		return
	var list: Array = _streams[name]
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = list[_rng.range_i(0, list.size() - 1)]
	p.volume_db = volume_db + linear_to_db(maxf(0.001, sfx_volume))
	p.pitch_scale = 1.0 + _rng.range_f(-pitch_jitter, pitch_jitter)
	p.play()


## 按距离衰减着播（远处的声音小一点，避免混成一锅粥）
func play_at(name: String, dist_px: float, max_dist: float = 1400.0, volume_db: float = 0.0) -> void:
	if dist_px >= max_dist:
		return
	var k := 1.0 - dist_px / max_dist
	play(name, volume_db + linear_to_db(maxf(0.05, k)), 0.08)


## 音量设置联动（Settings 里改音量时调它）
func set_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, sfx_volume)))


func has_sound(name: String) -> bool:
	return _streams.has(name)


func loaded_count() -> int:
	var n := 0
	for k in _streams.keys():
		n += (_streams[k] as Array).size()
	return n
