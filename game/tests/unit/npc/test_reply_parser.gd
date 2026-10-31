extends GutTest


func test_speech_and_meta() -> void:
	var r: Dictionary = ReplyParser.parse('Ah, Mr. Underhill!\n---META---\n{"options": ["a", "b"], "intents": [{"type": "disposition_delta", "value": 1}], "mood": "flustered"}')
	assert_eq(r["speech"], "Ah, Mr. Underhill!")
	assert_eq(r["options"], ["a", "b"])
	assert_eq((r["intents"] as Array).size(), 1)
	assert_eq(r["mood"], "flustered")
	assert_true(r["meta_ok"])


func test_missing_meta_keeps_speech() -> void:
	var r: Dictionary = ReplyParser.parse("  Just talking, no meta.  ")
	assert_eq(r["speech"], "Just talking, no meta.")
	assert_eq(r["options"], [])
	assert_eq(r["intents"], [])
	assert_false(r["has_meta"])


func test_broken_json_gives_no_options_or_intents() -> void:
	var r: Dictionary = ReplyParser.parse('Hello there.\n---META---\n{"options": ["a", ')
	assert_eq(r["speech"], "Hello there.")
	assert_eq(r["options"], [])
	assert_eq(r["intents"], [])
	assert_true(r["has_meta"])
	assert_false(r["meta_ok"])
	assert_push_warning_count(1)


func test_meta_with_no_speech() -> void:
	var r: Dictionary = ReplyParser.parse('---META---\n{"options": ["x"], "intents": []}')
	assert_eq(r["speech"], "")
	assert_eq(r["options"], ["x"])


func test_meta_in_code_fence_and_trailing_prose() -> void:
	var r: Dictionary = ReplyParser.parse('Hi.\n---META---\n```json\n{"options": ["x"], "intents": []}\n```\nHope that helps!')
	assert_eq(r["options"], ["x"])
	assert_true(r["meta_ok"])


func test_bad_shapes_are_filtered() -> void:
	var r: Dictionary = ReplyParser.parse('Hi.\n---META---\n{"options": ["a", 5, "", "b", "c", "d", "e"], "intents": ["nope", {"type": 3}, {"type": "end_conversation"}], "mood": 7}')
	assert_eq(r["options"], ["a", "b", "c", "d"], "non-strings dropped and capped at max_options")
	assert_eq(r["intents"], [{"type": "end_conversation"}])
	assert_eq(r["mood"], "")


func test_meta_json_not_an_object() -> void:
	var r: Dictionary = ReplyParser.parse("Hi.\n---META---\n[1, 2]")
	assert_false(r["meta_ok"])
	assert_push_warning_count(1)


func _stream(chunks: Array[String]) -> Array:
	var s := ReplyParser.SpeechStream.new()
	var shown: String = ""
	for c in chunks:
		shown += s.feed(c)
	shown += s.finish()
	return [shown, s]


func test_stream_stops_at_marker_split_across_chunks() -> void:
	var out: Array = _stream(["Ah, good ", "evening!\n--", "-MET", "A---\n{\"options\": []}"])
	assert_eq(out[0], "Ah, good evening!")
	assert_true((out[1] as ReplyParser.SpeechStream).meta_seen)
	assert_eq(ReplyParser.parse((out[1] as ReplyParser.SpeechStream).full_text)["speech"], "Ah, good evening!")


func test_stream_releases_false_marker_prefix() -> void:
	var out: Array = _stream(["Well -- ", "-- that is odd --", "- indeed"])
	assert_eq(out[0], "Well -- -- that is odd --- indeed")


func test_stream_without_marker_flushes_partial_prefix_on_finish() -> void:
	var out: Array = _stream(["Wait ---ME"])
	assert_eq(out[0], "Wait ---ME")
	assert_false((out[1] as ReplyParser.SpeechStream).meta_seen)


func test_stream_never_emits_marker_char_by_char() -> void:
	var chunks: Array[String] = []
	for ch in "Hello.\n---META---\n{}":
		chunks.append(ch)
	var out: Array = _stream(chunks)
	assert_eq(out[0], "Hello.")
