class_name Skills
extends RefCounted
## Hidden, use-based skill XP. The player never sees numbers; only the tier effects and the
## "player skill" lines handed to NPC prompts reveal progress. XP lives in the player entity data.

const DATA_KEY: String = "skills"

var _state: Node


func _init(state: Node = null) -> void:
	_state = state if state != null else WorldState


func skill_ids() -> Array:
	return Tuning.list("skills.ids")


func xp(skill: String) -> float:
	return float(_store().get(skill, 0.0))


## Number of thresholds passed (0 = untrained).
func tier(skill: String) -> int:
	var reached: int = 0
	var value: float = xp(skill)
	for t: Variant in Tuning.list("skills.thresholds"):
		if value >= float(t):
			reached += 1
	return reached


## Adds XP, returns the number of newly unlocked tiers. Unknown skills are ignored.
func add_xp(skill: String, amount: float) -> int:
	if amount <= 0.0 or not skill_ids().has(skill):
		return 0
	var before: int = tier(skill)
	_store()[skill] = minf(xp(skill) + amount, Tuning.num("skills.xp_max"))
	var after: int = tier(skill)
	for t: int in range(before + 1, after + 1):
		EventBus.skill_unlocked.emit(skill, t)
	return after - before


## Awards the XP configured for a named action (e.g. "forage"). Returns false for unknown actions.
func record_action(action: String, scale: float = 1.0) -> bool:
	var def: Dictionary = Tuning.dict("skills.actions").get(action, {})
	if def.is_empty():
		return false
	add_xp(str(def["skill"]), float(def["xp"]) * scale)
	return true


## Merged value of an effect key across every unlocked tier of every skill. Multipliers combine
## by product and bonuses by sum, picked by the key's suffix; absent effects give the neutral value.
func effect(key: String) -> float:
	var multiplicative: bool = key.ends_with("_multiplier")
	var result: float = 1.0 if multiplicative else 0.0
	for skill: String in skill_ids():
		var tiers: Array = Tuning.list("skills.tiers.%s" % skill)
		for i in range(mini(tier(skill), tiers.size())):
			var fx: Dictionary = (tiers[i] as Dictionary).get("effect", {})
			if not fx.has(key):
				continue
			if multiplicative:
				result *= float(fx[key])
			else:
				result += float(fx[key])
	return result


## One line per trained skill, describing only the highest unlocked tier.
func prompt_lines() -> Array[String]:
	var lines: Array[String] = []
	for skill: String in skill_ids():
		var reached: int = tier(skill)
		var tiers: Array = Tuning.list("skills.tiers.%s" % skill)
		if reached == 0 or tiers.is_empty():
			continue
		var def: Dictionary = tiers[mini(reached, tiers.size()) - 1]
		lines.append("Player skill (%s): %s" % [skill, def.get("line", "")])
	return lines


func _store() -> Dictionary:
	if not _state.has_entity(WorldState.PLAYER_ID):
		_state.spawn_entity(WorldState.PLAYER_ID, "player")
	var data: Dictionary = (_state.entities[WorldState.PLAYER_ID] as Dictionary)["data"]
	if not data.has(DATA_KEY):
		data[DATA_KEY] = {}
	return data[DATA_KEY]
