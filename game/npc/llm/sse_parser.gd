class_name SSEParser
extends RefCounted
## Incremental Server-Sent-Events parser. Feed raw text as it arrives; get back
## the complete `data:` payloads. Comment lines (": OPENROUTER PROCESSING") are ignored.

var _buf: String = ""


func feed(text: String) -> Array[String]:
	var out: Array[String] = []
	_buf += text
	while true:
		var nl: int = _buf.find("\n")
		if nl < 0:
			break
		var line: String = _buf.substr(0, nl).strip_edges(false, true)
		_buf = _buf.substr(nl + 1)
		if line.begins_with(":") or line.is_empty():
			continue
		if line.begins_with("data:"):
			out.append(line.substr(5).strip_edges())
	return out
