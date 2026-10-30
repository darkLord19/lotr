class_name SoftFailure
extends RefCounted
## Soft failure from a Black Rider: faint, lose time, Black Breath debuff, a Shire rumour,
## and occasionally a robbery. Dependencies are injected so tests can use fresh instances;
## by default it uses the live autoloads.

const BLACK_BREATH_FLAG: String = "debuff.black_breath_until"
const RUMOUR_SUBJECT_FLAG_PREFIX: String = "rumour_subject."
const KIND: String = "black_rider_caught"

var _state: Node
var _clock: Node
var _rng: RandomNumberGenerator


func _init(state: Node = null, clock: Node = null, rng: RandomNumberGenerator = null) -> void:
	_state = state if state != null else WorldState
	_clock = clock if clock != null else WorldClock
	_rng = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		_rng.randomize()


static func _cfg(key: String, default: Variant) -> Variant:
	return Config.get_value("soft_failure." + key, default)


## Applies every effect and returns a summary: {minutes, black_breath_until, robbed: Array[String]}.
func apply(player_name: String, player_race: String) -> Dictionary:
	var minutes: int = _rng.randi_range(int(_cfg("faint_min_minutes", 120)), int(_cfg("faint_max_minutes", 360)))
	_clock.advance(minutes)
	# The debuff starts when the player wakes, so the full duration is felt.
	var until: int = int(_clock.now) + int(_cfg("black_breath_hours", 12)) * int(_clock.MINUTES_PER_HOUR)
	_state.set_flag(BLACK_BREATH_FLAG, until)
	_spread_rumour(player_name)
	var robbed: Array[String] = []
	if player_race != str(_cfg("hobbit_race", "hobbit")) and _rng.randf() < float(_cfg("robbery_chance", 0.15)):
		robbed = _rob()
	var summary: Dictionary = {"minutes": minutes, "black_breath_until": until, "robbed": robbed}
	EventBus.player_failed.emit(KIND, summary)
	return summary


## Stamina multiplier the survival/movement code should apply; 1.0 once the debuff expires.
func stamina_multiplier() -> float:
	return float(_cfg("black_breath_stamina_factor", 0.5)) if black_breath_active() else 1.0


func black_breath_active() -> bool:
	return int(_state.get_flag(BLACK_BREATH_FLAG, 0)) > int(_clock.now)


# The rumour text lives in content with a {player} placeholder; the subject is a flag so the
# rumour network can fill it in later and the id stays a valid content id.
func _spread_rumour(player_name: String) -> void:
	var rid: String = str(_cfg("rumour_id", "player_found_senseless"))
	_state.set_flag(RUMOUR_SUBJECT_FLAG_PREFIX + rid, player_name)
	_state.spread_rumour(rid, str(_cfg("shire_rumour_poi", "bywater")))


func _rob() -> Array[String]:
	var stolen: Array[String] = []
	var inv: Dictionary = _state.inventories.get(WorldState.PLAYER_ID, {})
	var items: Array = inv.keys()
	items.sort()  # deterministic order so a seeded RNG gives reproducible theft
	for i in range(mini(int(_cfg("robbery_max_stacks", 1)), items.size())):
		var idx: int = _rng.randi_range(0, items.size() - 1)
		var item: String = items[idx]
		items.remove_at(idx)
		if _state.transfer_item(item, WorldState.PLAYER_ID, "", int(inv[item])):
			stolen.append(item)
	return stolen
