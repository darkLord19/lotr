class_name MockTransport
extends LLMTransport
## Replays canned SSE text. Each entry of `canned` is a raw string fed to the SSE parser
## (it may split lines arbitrarily). If `stall` is true the stream never ends (timeout tests).
## If `synchronous` is true, everything replays inside start(); otherwise one entry per poll().

var canned: Array[String] = []
var fail_with: String = ""  ## non-empty: finish(false, fail_with) after the script
var stall: bool = false
var synchronous: bool = true
var last_url: String = ""
var last_headers: PackedStringArray = PackedStringArray()
var last_body: String = ""

var _parser: SSEParser = SSEParser.new()
var _idx: int = 0
var _done: bool = false


static func sse(obj: Variant) -> String:
	return "data: %s\n\n" % (obj if obj is String else JSON.stringify(obj))


static func delta(text: String) -> String:
	return sse({"choices": [{"delta": {"content": text}}]})


func start(url: String, headers: PackedStringArray, body: String) -> void:
	last_url = url
	last_headers = headers
	last_body = body
	if synchronous:
		while not _done:
			poll()


func poll() -> void:
	if _done:
		return
	if _idx < canned.size():
		var chunk: String = canned[_idx]
		_idx += 1
		for payload in _parser.feed(chunk):
			data_received.emit(payload)
		return
	if stall:
		if synchronous:
			_done = true  # can't spin forever; gateway timeout is tested with synchronous=false
		return
	_done = true
	finished.emit(fail_with.is_empty(), fail_with)


func cancel() -> void:
	_done = true
