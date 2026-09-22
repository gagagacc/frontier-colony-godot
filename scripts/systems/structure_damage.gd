## 敌人拆建筑 —— 对应 JS `enemies.damageBuilding()` 与 `runState.damageBase()`。
##
## 之前 Godot 版的怪**只打玩家**：`_attack()` 里只有 `player.take_damage`。
## 后果是「基地被摧毁 → 追杀阶段」「塔被打掉」这两条主循环在 Godot 版**根本走不到**
## （只有断言在测它们）。这个文件把这条路径补上。
##
## 规则照抄 JS：
##   - 塔 / 建筑：hp 归零就标记 `destroyed`，从列表里移除；
##   - 基地：hp 归零 → `destroyed = true`，同时**让波次导演切进追杀模式**、
##     并清空城镇人口（JS 的 `popDeathOnDestroy`）。
class_name StructureDamage


## 打一个塔或建筑。返回是否被打掉。
static func hit_building(b: Dictionary, amount: float, rng: Rng) -> bool:
	if GdMath.truthy(b.get("destroyed", false)):
		return false
	var hp := float(b.get("hp", 0.0)) - maxf(0.0, amount)
	# 受击闪白：渲染层用它做反馈
	b["hitFlash"] = 1.0
	if hp > 0.0:
		b["hp"] = hp
		return false
	b["hp"] = 0.0
	b["destroyed"] = true
	return true


## 打基地。返回 `{ destroyed: bool, justDestroyed: bool }`
##
## `popDeathOnDestroy` 与 `rebuildTime` 都来自 `config.json` 的 BASE 表（不手抄）。
static func hit_base(b: Dictionary, amount: float, base_def: Dictionary) -> Dictionary:
	if GdMath.truthy(b.get("destroyed", false)):
		return { "destroyed": true, "justDestroyed": false }
	var hp := float(b.get("hp", 0.0)) - maxf(0.0, amount)
	b["hitFlash"] = 1.0
	if hp > 0.0:
		b["hp"] = hp
		return { "destroyed": false, "justDestroyed": false }
	b["hp"] = 0.0
	b["destroyed"] = true
	b["repairProgress"] = 0.0
	return { "destroyed": true, "justDestroyed": true }


## 基地被打掉时要做的连锁反应（JS 里散在 damageBase / director 里）
##   - 波次导演切追杀模式
##   - 城镇人口清零（BASE.popDeathOnDestroy）
static func on_base_destroyed(director, town, base_def: Dictionary) -> String:
	var lines: Array = []
	if director != null and director.has_method("start_hunt"):
		director.start_hunt("baseLost")
		lines.append("虫群转入追杀")
	if town != null and float(base_def.get("popDeathOnDestroy", 1.0)) > 0.0:
		town.population = 0
		lines.append("人口清零")
	return " · ".join(lines)
