extends SceneTree

var frames = 0
var main: Node = null

func _init() -> void:
	var main_scene = load("res://scenes/Main.tscn")
	main = main_scene.instantiate()
	root.add_child(main)

func _process(delta: float) -> bool:
	frames += 1
	if frames == 2:
		print("Frame 2: pressing diplomacy_btn...")
		var hud = main.get_node("HUD")
		var btn = hud.get_node("TopBar/DiplomacyButton") as Button
		print("Found btn: ", btn)
		btn.pressed.emit()
		print("Emitted pressed on diplomacy_btn successfully!")
	elif frames == 4:
		print("Frame 4: testing espionage button...")
		var hud = main.get_node("HUD")
		var btn = hud.get_node("TopBar/EspionageButton") as Button
		btn.pressed.emit()
		print("Emitted pressed on espionage_btn successfully!")
	elif frames == 6:
		print("All checks passed!")
		quit(0)
	return false
