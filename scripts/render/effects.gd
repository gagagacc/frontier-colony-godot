## 打击特效 —— 用 GPU 粒子，而不是 Canvas 那样手画圆圈。
##
## 审计里的第 2 项空白：JS 侧 0 处粒子（特效全靠 `effects.push({kind:'claw'})` 再手绘），
## Godot 有 `GPUParticles2D` —— 好处是**粒子在 GPU 上算**，
## 命中火花几十上百颗也不会拖累主线程（Canvas 的 `arc()` 每颗都要一次 CPU 调用）。
##
## 贴图是程序化生成的 8×8 柔光点，不引素材。
class_name Effects

const POOL := 10

var root: Node2D = null
var _emitters: Array[GPUParticles2D] = []
var _next := 0


func setup(host: Node) -> void:
	root = Node2D.new()
	root.name = "Effects"
	host.add_child(root)
	var tex := _dot_texture()
	for i in POOL:
		var p := GPUParticles2D.new()
		p.texture = tex
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 16
		p.lifetime = 0.5
		p.local_coords = false
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(1, 0, 0)
		mat.spread = 180.0
		mat.initial_velocity_min = 40.0
		mat.initial_velocity_max = 220.0
		mat.gravity = Vector3(0, 240, 0)
		mat.scale_min = 0.4
		mat.scale_max = 1.2
		mat.damping_min = 60.0
		mat.damping_max = 160.0
		p.process_material = mat
		root.add_child(p)
		_emitters.append(p)


## 8×8 柔光点（中间白、边缘透明）
static func _dot_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var d := Vector2(float(x) - 3.5, float(y) - 3.5).length() / 4.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## 爆一小簇粒子。`count` 越大越夸张（击杀 > 命中）
func burst(pos: Vector2, color: Color, count: int = 10, speed: float = 1.0) -> void:
	if _emitters.is_empty():
		return
	var p := _emitters[_next]
	_next = (_next + 1) % _emitters.size()
	p.position = pos
	p.amount = maxi(4, count)
	p.lifetime = 0.35 + 0.25 * speed
	p.modulate = color
	var mat := p.process_material as ParticleProcessMaterial
	if mat != null:
		mat.initial_velocity_min = 40.0 * speed
		mat.initial_velocity_max = 220.0 * speed
	p.restart()
	p.emitting = true
