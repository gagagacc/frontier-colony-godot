## 星球难度分级（5 级）—— 数据在 `data/planets.json` 的 `PLANET_DIFF`，
## 源头是 `src/data/planets.js`（改数值请改 JS 再跑 `tools/export-godot-data.mjs`）。
##
## 玩家指定的数值：
##   1 级：怪量 ×0.75，血量/伤害 ×0.75
##   2 级：怪量 ×0.90，血量/伤害 ×0.90
##   3 级：标准（全 ×1.00）
##   4 级：怪量 ×1.25，血量/伤害 ×1.15
##   5 级：怪量 ×1.35，血量/伤害 ×1.20，精英 ×1.25
##
## ## 三个乘数分别乘在哪里
##
##   · `count` → 导演的**刷怪预算**（`Director` 是"给预算买怪"，乘预算 = 乘数量）
##   · `hp` / `dmg` → 敌人工厂的 `hpMult` / `dmgMult`（`Enemies.spawn()` 统一注入，
##     所以怪潮、副本守军、`spawn_around`、召唤物全都一致；Boss 也走这条路）
##   · `elite` → 怪种池里**精英条目**的权重（只有 5 级动它）
class_name PlanetDiff

static var _table: Array = []
static var _names: int = 12
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var mod: Dictionary = DataLoader.new().module("planets")
	var t = mod.get("PLANET_DIFF", [])
	if t is Array and not (t as Array).is_empty():
		_table = t
	var n = mod.get("PLANET_NAMES", [])
	if n is Array and not (n as Array).is_empty():
		_names = (n as Array).size()


## 星球序号 → 难度等级（1..5）。
## 与 JS `planetDiffLevel()` 同式：12 颗星球均摊五档 → 1/1/1/2/2/3/3/3/4/4/5/5
static func level_for(planet_index: int) -> int:
	_load()
	var span := maxi(1, _table.size())
	if _table.is_empty():
		return 3
	return clampi(1 + int(floor(float(maxi(0, planet_index)) * float(span) / float(maxi(1, _names)))),
		1, span)


## 该星球的难度条目（含乘数与中文名）
static func entry(planet_index: int) -> Dictionary:
	_load()
	if _table.is_empty():
		return {}
	return _table[level_for(planet_index) - 1]


static func count_mult(planet_index: int) -> float:
	return float(entry(planet_index).get("count", 1.0))


static func hp_mult(planet_index: int) -> float:
	return float(entry(planet_index).get("hp", 1.0))


static func dmg_mult(planet_index: int) -> float:
	return float(entry(planet_index).get("dmg", 1.0))


static func elite_mult(planet_index: int) -> float:
	return float(entry(planet_index).get("elite", 1.0))


static func name_of(planet_index: int) -> String:
	return String(entry(planet_index).get("name", "标准"))


static func desc_of(planet_index: int) -> String:
	return String(entry(planet_index).get("desc", ""))


## 给界面用的一行说明：「怪量 ×0.75 · 血量/伤害 ×0.75」
static func summary(planet_index: int) -> String:
	var e := entry(planet_index)
	if e.is_empty():
		return ""
	var parts: Array = ["怪量 ×%.2f" % float(e.get("count", 1.0)),
		"血量/伤害 ×%.2f" % float(e.get("hp", 1.0))]
	if absf(float(e.get("elite", 1.0)) - 1.0) > 0.001:
		parts.append("精英 ×%.2f" % float(e.get("elite", 1.0)))
	return " · ".join(parts)
