class_name Tuning
extends RefCounted
## Typed accessors over Config for the survival tunables. A missing key is a config bug, so it
## warns loudly instead of silently inventing a default number in gameplay code.


static func num(path: String) -> float:
	var v: Variant = Config.get_value(path)
	if v == null:
		push_warning("Tuning: missing config %s" % path)
		return 0.0
	return float(v)


static func integer(path: String) -> int:
	return int(num(path))


static func text(path: String) -> String:
	return str(Config.get_value(path, ""))


static func dict(path: String) -> Dictionary:
	var v: Variant = Config.get_value(path, {})
	return v if v is Dictionary else {}


static func list(path: String) -> Array:
	var v: Variant = Config.get_value(path, [])
	return v if v is Array else []
