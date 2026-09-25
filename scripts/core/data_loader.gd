## 数据表加载器：读 `res://data/*.json`（由 `tools/export-godot-data.mjs` 从 JS 版导出）。
##
## 所有内容（科技树、武器、怪物、地块、角色、实验科技……）都以 JSON 为准，
## Godot 侧不再手抄一份 —— 这样 JS 版改数值时只要重新导出即可。
class_name DataLoader

const DATA_DIR := "res://data/"

## 怪物表缓存（补过 id 的那份）
static var _monster_cache: Dictionary = {}


## 怪物定义表，**每条都补上了 `id`**（= 表里的键）。
##
## ## 为什么必须补
##
## `MONSTER_DEF` 里的条目**本身没有 `id` 字段**（键才是 id）。而实体创建时写的是
## `monster_def.get("id", "")` —— 拿到空串，于是怪物贴图查找走的是
## `def.get("id", e.get("kind"))` = 实体类型 `"enemy"`，
## 去找 `enemy_enemy_s.png`（当然没有）→ **每次都退回单图旋转**。
## 玩家看到的「怪根本没切换贴图、只是在转」就是这个：三视图做了、也装了，但**取不到**。
##
## 所以统一在这里把键写回条目里，调用方（导演/敌人工厂/名字表）拿到的都是带 id 的定义。
static func monster_defs() -> Dictionary:
	if not _monster_cache.is_empty():
		return _monster_cache
	var table: Dictionary = DataLoader.new().table("monsters", "MONSTER_DEF", {})
	for k in table.keys():
		var d = table[k]
		if d is Dictionary and String((d as Dictionary).get("id", "")) == "":
			(d as Dictionary)["id"] = String(k)
	_monster_cache = table
	return _monster_cache

var _cache: Dictionary = {}
var index: Dictionary = {}


func _init() -> void:
	load_index()


func load_index() -> Dictionary:
	index = _load_json("index.json")
	return index


func _load_json(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var path := DATA_DIR + name
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_warning("数据表读不到：%s（先跑 node tools/export-godot-data.mjs）" % path)
		_cache[name] = {}
		return {}
	var parsed = JSON.parse_string(text)
	var dict: Dictionary = parsed if parsed is Dictionary else {}
	_cache[name] = dict
	return dict


## 取某个模块的整张表，例如 module("tiles").get("TILE_DEF", {})
func module(mod: String) -> Dictionary:
	return _load_json(mod + ".json")


## 取一张表：table("tiles", "PROP_DEF")
func table(mod: String, key: String, fallback = {}) -> Variant:
	var m := module(mod)
	return m.get(key, fallback)


## 从数据表里取数字。
##
## **必须走这里，不能直接 `def.get("dmg", 10.0)`**：JS 的 `undefined` 序列化成 JSON 是
## `null`，而 `Dictionary.get(key, default)` 只在**键不存在**时给默认值 ——
## 键存在但值是 null 时会返回 null，`float(null)` 变成 0。
## 实测就是「无人机平台 / 力场塔的伤害变成 0」（JS 那边 `(d.dmg || 10)` 会兜住）。
static func num(d, key: String, def: float = 0.0) -> float:
	if d is Dictionary:
		var v = d.get(key)
		if v is float or v is int:
			return float(v)
	return def


## 复刻 JS 的 `d.x || 默认值` 语义：**0 也算「没值」**。
##
## 为什么必须区分：`runState.createTower` 写的是 `(def.dmg || 10)` ——
## 支援塔（无人机平台 / 力场塔）的数据里 `dmg` 就是 0，JS 会兜到 10；
## 若这边用「只在缺失时兜底」的 num()，就会算出 0 伤害，两边对不上。
static func num_or(d, key: String, def: float = 0.0) -> float:
	var v := num(d, key, 0.0)
	return def if v == 0.0 else v


static func int_of(d, key: String, def: int = 0) -> int:
	return int(num(d, key, float(def)))


static func str_of(d, key: String, def: String = "") -> String:
	if d is Dictionary:
		var v = d.get(key)
		if v is String:
			return v
	return def


static func bool_of(d, key: String, def: bool = false) -> bool:
	if d is Dictionary:
		var v = d.get(key)
		if v is bool:
			return v
		if v is float or v is int:
			return float(v) != 0.0
	return def


## 按 id 建索引，方便 O(1) 查表：[{ id = ... }, ...] -> { id: entry }
static func by_id(entries) -> Dictionary:
	var out: Dictionary = {}
	if entries is Array:
		for e in entries:
			if e is Dictionary and e.has("id"):
				out[String(e["id"])] = e
	elif entries is Dictionary:
		for k in entries.keys():
			var v = entries[k]
			if v is Dictionary:
				out[String(v.get("id", k))] = v
			else:
				out[String(k)] = v
	return out


## 汇总（启动时打印，用来确认数据管线通了）
func summary() -> String:
	var mods: Array = index.get("modules", [])
	if mods.is_empty():
		return "数据未导出（godot/data/index.json 缺失）"
	var lines: Array = []
	var total := 0
	for m in mods:
		var counts: Dictionary = m.get("counts", {})
		var n := 0
		for k in counts.keys():
			n += int(counts[k])
		total += n
		lines.append("%s（%d 张表 / %d 条）" % [m.get("module", "?"), m.get("tables", []).size(), n])
	return "%d 个模块 / %d 条数据\n%s" % [mods.size(), total, "\n".join(lines)]
