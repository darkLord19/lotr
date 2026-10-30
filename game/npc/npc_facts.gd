class_name NPCFacts
extends RefCounted
## What an NPC can truthfully know, own or reveal right now. Shared by the prompt builder (what
## the model is told) and the intent validator (what the model may propose), so they never disagree.


static func location(npc_id: String, card: Dictionary) -> String:
	var poi: String = str(WorldState.entity_location(npc_id).get("poi", ""))
	return poi if poi != "" else str(card.get("home_poi", ""))


## Entries with known_from <= now and a satisfied requires_flag, plus entries a timeline effect
## granted via WorldState.add_knowledge (their flag still has to hold).
static func visible_knowledge(npc_id: String, card: Dictionary, now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: Variant in card.get("knowledge", []):
		var entry: Dictionary = k
		var flag: Variant = entry.get("requires_flag")
		if flag is String and not (flag as String).is_empty() and not bool(WorldState.get_flag(flag)):
			continue
		var from: int = GameDate.parse(str(entry.get("known_from", "")))
		var dated: bool = from != GameDate.INVALID and from <= now
		if dated or WorldState.has_knowledge(npc_id, str(entry.get("id", ""))):
			out.append(entry)
	return out


## Item ids from the card's give-list that the NPC still holds.
static func giftable_items(npc_id: String, card: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for item: Variant in card.get("inventory_can_give", []):
		if WorldState.item_count(npc_id, str(item)) > 0:
			out.append(str(item))
	return out


## Rumour ids present at the NPC's POI or anywhere in its settlement.
static func heard_rumours(npc_id: String, card: Dictionary) -> Array[String]:
	var here: String = location(npc_id, card)
	var settlement: String = str((WorldState.poi_info.get(here, {}) as Dictionary).get("settlement", ""))
	var out: Array[String] = []
	for rid: String in WorldState.rumours:
		for poi: Variant in WorldState.rumours[rid]:
			var p: String = str(poi)
			var same_place: bool = p == here
			var same_settlement: bool = settlement != "" and str((WorldState.poi_info.get(p, {}) as Dictionary).get("settlement", "")) == settlement
			if same_place or same_settlement:
				out.append(rid)
				break
	return out


## POIs the NPC could point the player to: registered POIs in its own settlement first.
static func revealable_pois(npc_id: String, card: Dictionary) -> Array[String]:
	var here: String = location(npc_id, card)
	var settlement: String = str((WorldState.poi_info.get(here, {}) as Dictionary).get("settlement", ""))
	var near: Array[String] = []
	var far: Array[String] = []
	for poi: String in WorldState.poi_info:
		if poi == here:
			continue
		var same: bool = settlement != "" and str((WorldState.poi_info[poi] as Dictionary).get("settlement", "")) == settlement
		(near if same else far).append(poi)
	near.sort()
	far.sort()
	near.append_array(far)
	return near.slice(0, int(Config.get_value("npc.max_reveal_pois", 12)))


static func band_name(bands_path: String, value: int) -> String:
	var name: String = ""
	for b: Variant in Config.get_value(bands_path, []):
		if value >= int((b as Dictionary).get("min", 0)):
			name = str((b as Dictionary).get("name", ""))
	return name
