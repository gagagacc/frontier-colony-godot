## Laya 托管 —— 让本地 Laya 决策模型**真的来玩这个游戏**。
##
## ## 为什么是"高层决策 + 底层交给人机系统"
##
## Laya 是**类型化决策路由器**：喂一段文本状态 + 若干 choice/score/noul 问题，返回答案。
## 实测单次推理 **≈400 ms**（本机 127.0.0.1:8199）。这个延迟：
##   · 做「这一轮干什么」这类决策绰绰有余（0.8 秒一次）；
##   · 做「每一帧往哪转、什么时候开枪」完全不够（那是 60 Hz 的事）。
## 所以分工是：**Laya 决定意图（engage/retreat/hunt/gather/build），
## 本文件负责把意图翻译成操作**（走位、瞄准、开火、落塔），复用手感已经调好的现有系统。
##
## ## 接口
##
##   POST http://127.0.0.1:8199/v1/systemone
##   { "state": "…", "questions": { "stance": { "type":"choice", "instructions":"…",
##     "criteria": { "engage":"…", "retreat":"…" } }, … } }
##   → { "answers": { "stance": { "choice":"engage", "confidence":0.06 }, … }, "routing": {…} }
##
## ⚠️ 本机这份 checkpoint 的 temperature 有问题（启动时会警告），**置信度不可当真**，
##    只取 argmax 的选项；置信度照旧显示在 HUD 上，但别拿它做阈值判断。
##
## 服务器没起 / 请求失败时**不报错不崩**：记一条日志、保持上一个意图继续执行。
class_name LayaBot
extends Node

const ENDPOINT := "http://127.0.0.1:8199/v1/systemone"
const DECIDE_INTERVAL := 0.8      # 秒：两次决策之间至少隔这么久
const ENEMY_NEAR := 520.0         # "附近有威胁"的判定半径（像素）
const FIRE_RANGE_MARGIN := 0.92   # 武器射程的多少比例内才开火

var game = null                   # Game（Node）
var enabled := false
var intent := "idle"
var intent_conf := 0.0
var build_choice := "none"
var danger := 0.0
var want_retreat := false
var last_ms := 0
var last_state := ""
var ask_count := 0
var fail_count := 0

var _timer := 0.0
var _busy := false
## 连续选了同一个意图的次数（用来打破"自我确认"循环，写进状态文本里提醒模型）
var _same_intent_streak := 0
## 本轮决策是否已经尝试过建造（避免每帧都去落塔 → 资源瞬间被刷光）
var _built_this_round := false
var _tower_defs: Dictionary = {}
var _http: HTTPRequest = null
var _target: Variant = null       # 当前追踪的目标（怪/巢/道具）


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_response)


## 每个逻辑帧调用（由 Game 在 playing 且未暂停时调用）
func tick(dt: float) -> void:
	if not enabled or game == null:
		return
	_timer -= dt
	if _timer <= 0.0 and not _busy:
		_timer = DECIDE_INTERVAL
		_ask()
	_execute(dt)


# =========================================================
#  ① 决策：把局势写成一段文本，问 Laya
# =========================================================

func _ask() -> void:
	var state := _describe_state()
	last_state = state
	var questions := {
		# ⚠️ 多选一（choice）在这类**路由模型**上会"死盯一个选项"：
		#    实测第一版 94/94 全选 retreat，换成带判据的措辞后又 112/117 全选 build，
		#    而且 build 配上 build_what=none 自相矛盾 —— 说明它是在独立地挑每个问题里
		#    最显著的选项，而不是真的在读战报。
		#    改成**一组是非题**：每件事单独问"现在该不该做"，再取概率最高的那个"是"。
		"do_engage": { "type": "noul", "instructions": "现在应该就地开火，清掉正在逼近的虫子吗？" },
		"do_retreat": { "type": "noul", "instructions": "现在应该立刻撤回核心舱附近吗？" },
		"do_hunt": { "type": "noul", "instructions": "现在应该主动前出去拆虫巢吗？" },
		"do_gather": { "type": "noul", "instructions": "现在应该先去采集资源吗？" },
		"do_build": { "type": "noul", "instructions": "现在应该建造一座防御塔吗？" },
		"build_what": {
			"type": "choice",
			"instructions": "如果上面决定要建造，建哪一种？（**只有**在资源连最便宜的塔都不够时才选 none）",
			"criteria": {
				"sentry": "最便宜的基础机枪塔（最省）",
				"gatling": "中价的转管机炮",
				"mortar": "范围杀伤的迫击炮",
				"rail": "昂贵但高伤的磁轨炮",
				"none": "资源不够造任何塔",
			},
		},
		"danger": {
			"type": "score",
			"instructions": "当前处境有多危险？",
			"criteria": ["平静", "紧张", "危急"],
		},
	}
	var body := JSON.stringify({ "state": state, "questions": questions })
	var err := _http.request(ENDPOINT, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body)
	if err != OK:
		fail_count += 1
		print("[laya] 请求发不出去（%d）—— 后端没起？保持上一个意图" % err)
		return
	_busy = true
	ask_count += 1
	_built_this_round = false
	_t0 = Time.get_ticks_msec()


var _t0 := 0


## 把局势压成一段**短文本**：模型读的是自然语言，太长反而抓不住重点
func _describe_state() -> String:
	var p = game.player
	var near = _nearest_enemy(ENEMY_NEAR)
	var base_hp := 0.0
	var base_max := 1.0
	if not game.towers.bases.is_empty():
		var b: Dictionary = game.towers.bases[0]
		base_hp = float(b.get("hp", 0.0))
		base_max = maxf(1.0, float(b.get("maxHp", 1.0)))
	var res := ""
	if game.props_layer != null:
		var parts: Array = []
		for k in ["metal", "crystal", "food", "parts"]:
			parts.append("%s %d" % [k, int(float(game.props_layer.resources.get(k, 0.0)))])
		res = "、".join(parts)
	var nest_d := 99999.0
	for n in game.world.nests:
		if GdMath.truthy(n.get("destroyed", false)):
			continue
		nest_d = minf(nest_d, GdMath.dist(p.position.x, p.position.y, float(n["x"]), float(n["y"])))
	var enemy_line := "附近没有敌人"
	if near != null:
		enemy_line = "最近的虫子在 %.0f 像素外（生命 %d/%d）" % [
			GdMath.dist(p.position.x, p.position.y, float(near["x"]), float(near["y"])),
			int(float(near["hp"])), int(float(near["hpMax"]))]
	# ⚠️ **绝对不要把"当前意图"写进状态里** —— 第一次实测 94 次决策全是 retreat：
	#    模型看到「当前意图：retreat」就只是确认它，形成自我强化循环。
	#    改成给**客观事实**（离核心舱多远、是否连着好几次选了同一件事），让它自己判断要不要换。
	var home_d := GdMath.dist(p.position.x, p.position.y, game.bases_pos.x, game.bases_pos.y)
	var home_line := "你已经在核心舱旁边（%.0f 像素）" % home_d if home_d < 260.0 \
		else "你离核心舱 %.0f 像素" % home_d
	var stuck_line := ""
	if _same_intent_streak >= 4:
		stuck_line = "另外：你最近连续 %d 次都选了「%s」，而局势没有明显变化 —— 请重新判断是否该改做别的事。" % [
			_same_intent_streak, intent]
	# 把「现在造得起哪些塔」直接写进状态：不写的话模型不知道价格，build 永远配 none
	var afford := _affordable_towers()
	var afford_line := "现在造得起：%s。" % (", ".join(afford) if not afford.is_empty() else "什么都造不起")
	return ("外星殖民地前线战报。玩家生命 %d/%d，弹药 %d/%d；%s。核心舱 %d/%d。%s。" +
		"最近的虫巢在 %.0f 像素外。资源：%s。已建防御塔 %d 座。%s%s") % [
		int(p.hp), int(p.hp_max), int(p.loadout.ammo), int(p.loadout.ammo_max), enemy_line,
		int(base_hp), int(base_max), home_line, nest_d, res, game.towers.towers.size(),
		afford_line, stuck_line]


## 以当前资源造得起的塔（带中文名与 id），给模型做判断
func _affordable_towers() -> Array:
	var out: Array = []
	if _tower_defs.is_empty():
		_tower_defs = DataLoader.new().table("towers", "TOWER_DEF", {})
	var res: Dictionary = game.props_layer.resources if game.props_layer != null else {}
	for id in game._unlocked_tower_ids():
		var d: Dictionary = _tower_defs.get(String(id), {})
		if d.is_empty():
			continue
		var cost: Dictionary = TowerMath.scale_cost(d.get("cost", {}), 1.0)
		var ok := true
		for k in cost.keys():
			if float(res.get(k, 0.0)) < float(cost[k]):
				ok = false
				break
		if ok:
			out.append("%s(%s)" % [Names.tower(String(id)), String(id)])
	return out


func _on_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	last_ms = Time.get_ticks_msec() - _t0
	if code != 200:
		fail_count += 1
		print("[laya] 后端返回 HTTP %d（%d ms）" % [code, last_ms])
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		fail_count += 1
		return
	var answers = (parsed as Dictionary).get("answers", {})
	if not (answers is Dictionary):
		return
	var a: Dictionary = answers
	# 是非题 → 意图：取**概率最高的那个"是"**（都是"否"就原地待命）
	var wants := {
		"retreat": float((a.get("do_retreat", {}) as Dictionary).get("noul", 0.0)),
		"engage": float((a.get("do_engage", {}) as Dictionary).get("noul", 0.0)),
		"hunt": float((a.get("do_hunt", {}) as Dictionary).get("noul", 0.0)),
		"gather": float((a.get("do_gather", {}) as Dictionary).get("noul", 0.0)),
		"build": float((a.get("do_build", {}) as Dictionary).get("noul", 0.0)),
	}
	# 优先级：撤退/交火是保命的，先看它们；都没过阈值再看 hunt/gather/build
	var picked := "idle"
	var best := 0.5
	for k in ["retreat", "engage", "hunt", "gather", "build"]:
		if float(wants[k]) > best:
			best = float(wants[k])
			picked = String(k)
	# 撤退单独再确认一次：概率高就强行撤退（保命优先于打分）
	want_retreat = float(wants["retreat"]) > 0.5
	if picked == intent:
		_same_intent_streak += 1
	else:
		_same_intent_streak = 0
	intent = picked
	intent_conf = best
	_target = null          # 换了意图就重新选目标
	if a.has("build_what"):
		build_choice = String((a["build_what"] as Dictionary).get("choice", "none"))
	if a.has("danger"):
		danger = float((a["danger"] as Dictionary).get("score", 0.0))
	var detail := ""
	for k in ["retreat", "engage", "hunt", "gather", "build"]:
		detail += "%s%.2f " % [String(k).substr(0, 3), float(wants[k])]
	print("[laya] 决策 #%d：%s（危险 %.2f%s）· 建造=%s · %d ms · 票 %s" % [
		ask_count, intent, danger, " · 建议撤退" if want_retreat else "", build_choice, last_ms, detail])


# =========================================================
#  ② 执行：把意图翻译成走位 / 瞄准 / 开火 / 落塔
# =========================================================

func _execute(dt: float) -> void:
	var p = game.player
	if p == null or p.loadout == null or p.world == null:
		return
	# 撤退优先 —— 但**只在真的还没撤到家时**才覆盖意图。
	# 否则会出现「已经站在核心舱旁边了还在一直撤退」这种死循环（第一次实测就是这样）。
	var home_d := GdMath.dist(p.position.x, p.position.y, game.bases_pos.x, game.bases_pos.y)
	var stance := "retreat" if (want_retreat and home_d > 320.0) else intent
	# 瞄准与开火：始终对着最近的敌人（这一层交给人机系统，模型不掺和）
	var near = _nearest_enemy(1400.0)
	if near != null:
		p.aim = GdMath.angle_to(p.position.x, p.position.y, float(near["x"]), float(near["y"]))
		var d := GdMath.dist(p.position.x, p.position.y, float(near["x"]), float(near["y"]))
		var reach := float(game._weapon_base_range()) * FIRE_RANGE_MARGIN
		if d <= reach:
			p.call("_fire")
	# 走位
	var goal = _goal_for(stance)
	if goal != null:
		var dir := Vector2(float(goal["x"]) - p.position.x, float(goal["y"]) - p.position.y)
		if dir.length() > 24.0:
			p.bot_dir = dir.normalized()
		else:
			p.bot_dir = Vector2.ZERO
			# 到位了就换目标（免得站着不动一直"想去做同一件事"）
			_target = null
	else:
		p.bot_dir = Vector2.ZERO
	# 建造：**一轮决策最多试一次**（之前是每帧都试，会把资源瞬间刷光）
	if stance == "build" and build_choice != "none" and not _built_this_round:
		_built_this_round = true
		_try_build(build_choice)


## 意图 → 目标点
##
## ⚠️ `game` 是无类型的（要能注入测试替身），所以**不能用 `:=` 从它推断类型** ——
##    `var b := game.bases_pos` 会直接编译失败（"Cannot infer the type"）。
##    凡是取自 game/player 的中间变量一律写 `=`（Variant）。
func _goal_for(stance: String) -> Variant:
	if _target != null and _target is Dictionary and _target.has("x"):
		return _target
	match stance:
		"retreat":
			var b = game.bases_pos
			_target = { "x": b.x, "y": b.y }
		"hunt":
			_target = _nearest_nest()
		"gather":
			_target = _nearest_prop()
		"build":
			# 建在基地附近：走到基地外圈再落塔
			var b2 = game.bases_pos
			_target = { "x": b2.x + 150.0, "y": b2.y + 60.0 }
		"engage":
			# 交火：朝最近敌人靠，但保持在射程内（贴上去反而挨打）
			var near = _nearest_enemy(1400.0)
			if near != null:
				var d := GdMath.dist(game.player.position.x, game.player.position.y,
					float(near["x"]), float(near["y"]))
				var reach := float(game._weapon_base_range()) * 0.75
				if d > reach:
					var f := reach / maxf(1.0, d)
					_target = {
						"x": lerpf(game.player.position.x, float(near["x"]), f),
						"y": lerpf(game.player.position.y, float(near["y"]), f),
					}
	return _target


func _try_build(tower_id: String) -> void:
	# `Towers.place_tower()` 用的是 `towers.selected`（没有 forceType 参数），
	# 所以先设好选中项再放 —— 别自己另写一条落塔路径，不然解锁校验/间隔规则会不一致。
	var p = game.player
	if not game.towers.selected == tower_id:
		game.towers.selected = tower_id
	var spot = game.world.find_open_spot(p.position.x + 60.0, p.position.y, 120.0)
	if spot == null:
		return
	var t: Dictionary = game.towers.place_tower(Vector2(float(spot["x"]), float(spot["y"])), {})
	if t.is_empty():
		return
	print("[laya] 执行建造：%s → (%.0f, %.0f)" % [tower_id, float(spot["x"]), float(spot["y"])])


func _nearest_enemy(max_d: float) -> Variant:
	var p = game.player
	var best = null
	var best_d := max_d
	for e in game.enemies.enemies:
		if GdMath.truthy(e.get("dead", false)):
			continue
		var d := GdMath.dist(p.position.x, p.position.y, float(e["x"]), float(e["y"]))
		if d < best_d:
			best_d = d
			best = e
	return best


func _nearest_nest() -> Variant:
	var p = game.player
	var best = null
	var best_d := 99999.0
	for n in game.world.nests:
		if GdMath.truthy(n.get("destroyed", false)):
			continue
		var d := GdMath.dist(p.position.x, p.position.y, float(n["x"]), float(n["y"]))
		if d < best_d:
			best_d = d
			best = { "x": float(n["x"]), "y": float(n["y"]) }
	return best


func _nearest_prop() -> Variant:
	var p = game.player
	if game.props == null:
		return null
	var pr = game.props.nearest(p.position.x, p.position.y, 1400.0)
	if pr == null:
		return null
	if pr is Dictionary and (pr as Dictionary).has("x"):
		return { "x": float(pr["x"]), "y": float(pr["y"]) }
	return null


## HUD 上那一行：让玩家看得见"它在想什么"
func hud_line() -> String:
	if not enabled:
		return ""
	var tag := "●" if _busy else "○"
	return "Laya %s %s · 危险 %.2f · 建造 %s · %d ms%s" % [
		tag, intent, danger, build_choice, last_ms,
		"（建议撤退）" if want_retreat else ""]
