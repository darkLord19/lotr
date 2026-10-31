extends Control
## Dev scene for captures: the dialogue panel over a plain backdrop, offline (authored greeting).
## tools/capture.sh res://tools/dialogue_stage.tscn out.png --npc=strider --date=3018-09-29T21:00 --after=1


func _ready() -> void:
	var npc: String = "barliman_butterbur"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--npc="):
			npc = a.substr(6)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.13, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel: DialoguePanel = (load("res://ui/dialogue/dialogue_panel.tscn") as PackedScene).instantiate() as DialoguePanel
	add_child(panel)
	panel.open(npc)
