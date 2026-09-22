
# =========================================================
#  HUD 补全（对齐 HTML 版的信息量）
# =========================================================
#
# 对着 HTML 版玩过之后发现：核心玩法一致，但 HUD 少了一半信息 ——
# 没有天数/昼夜、没有威胁值与活跃数、没有距离指示、资源条不全、没有快捷栏。
# 这里把缺的补上，**公式照抄 JS**（`src/ui/hud.js` 与 `runState._computeThreat`）。
#
# 纯函数放 HudModel 里（可断言），绘制与取值留在 Game 里。

class_name HudExtra

## 昼夜：JS 是 `phase = (time % 240) / 240`，再按阈值切四段（照抄）
static func day_phase_label(time_sec: float) -> String:
	var phase := fmod(maxf(0.0, time_sec), 240.0) / 240.0
	if phase < 0.12:
		return "黎明"
	if phase < 0.45:
		return "白昼"
	if phase < 0.58:
		return "黄昏"
	if phase < 0.92:
		return "夜晚"
	return "黎明"


## 「第 3 天 · 白昼 · 02:31」
static func day_text(time_sec: float, day: int) -> String:
	return "第 %d 天 · %s · %s" % [maxi(1, day), day_phase_label(time_sec), clock_text(time_sec)]


## 一天内的时刻（JS 的 fmtTime：把 0~240 秒映射成一整天）
static func clock_text(time_sec: float) -> String:
	var t := int(fmod(maxf(0.0, time_sec), 240.0))
	var minutes := int(float(t) / 240.0 * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## 局势标题（JS 的 wave_title 同构）
static func situation_title(state: int, number: int, hunt_mode: bool, beacon_online: bool) -> String:
	if hunt_mode:
		return "追杀阶段 · 基地已毁"
	if not beacon_online:
		return "吸引阵列离线"
	match state:
		Director.State.CALM:
			return "局势平稳 · 第 %d 波倒计时" % (number + 1)
		Director.State.INCOMING:
			return "第 %d 波正在逼近！" % number
		Director.State.ACTIVE:
			return "第 %d 波 · 交战中" % number
	return "局势平稳"


## 局势副标题：平静时给「还有多久 · 威胁 · 活巢」，交战给「剩余 · 基地耐久」
static func situation_sub(state: int, timer: float, remaining: int, total: int,
	threat_total: float, live_nests: int, base_hp: float, base_max: float) -> String:
	match state:
		Director.State.ACTIVE:
			return "剩余 %d/%d 只 · 基地耐久 %d/%d" % [remaining, total, int(ceilf(base_hp)), int(ceilf(base_max))]
		Director.State.INCOMING:
			return "%s 后抵达 · 共 %d 只" % [clock_text(timer), total]
		_:
			return "%s 后虫潮集结 · 威胁 %.1f · 活巢 %d" % [clock_text(timer), threat_total, live_nests]


## 距离指示：JS 用「米」，1 米 = 1 格（TILE）
static func distance_text(px: float) -> String:
	var meters := px / float(Cfg.TILE)
	if meters < 10.0:
		return "%.1fm" % meters
	return "%dm" % int(round(meters))


## 「基地 4m · 载具 4.2m · 巢穴 33.1m」（离得远的才显示，避免刷屏）
static func distance_line(base_px: float, vehicle_px: float, nest_px: float, has_vehicle: bool) -> String:
	var parts: Array = ["基地 " + distance_text(base_px)]
	if has_vehicle:
		parts.append("载具 " + distance_text(vehicle_px))
	if nest_px < 1.0e9:
		parts.append("巢穴 " + distance_text(nest_px))
	return " · ".join(parts)


## 资源条：顺序与 HTML 版一致（金币 / 金属 / 晶体 / 食物 / 零件 / 研究资料）
const RESOURCE_ORDER := ["gold", "metal", "crystal", "food", "parts", "research"]

static func resource_bar(res: Dictionary) -> String:
	var parts: Array = []
	for k in RESOURCE_ORDER:
		var v := int(float(res.get(k, 0.0)))
		var ic := Names.resource_icon(k)
		var nm := Names.resource(k)
		parts.append(("%s %d" % [nm, v]) if ic == "" else ("%s %s %d" % [ic, nm, v]))
	return "  ".join(parts)


## 快捷栏 8 格的文字（武器 4 格 + 道具 4 格）—— 每格「名字 ×数量」
static func hotbar_text(slots: Array) -> Array:
	var out: Array = []
	for i in 8:
		if i < slots.size():
			var s: Dictionary = slots[i]
			var nm := String(s.get("name", "（空）"))
			var cnt := int(s.get("count", 0))
			out.append(nm if cnt <= 1 else "%s×%d" % [nm, cnt])
		else:
			out.append("（空）")
	return out
