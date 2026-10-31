class_name LLMTransport
extends RefCounted
## Interface for a streaming POST. Implementations emit `data_received` once per SSE
## `data:` payload (including "[DONE]") and `finished` exactly once.

signal data_received(payload: String)
signal finished(ok: bool, error: String)


func start(_url: String, _headers: PackedStringArray, _body: String) -> void:
	push_error("LLMTransport.start not implemented")


# Called every frame by the gateway.
func poll() -> void:
	pass


func cancel() -> void:
	pass
