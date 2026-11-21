extends SceneTree

func _init() -> void:
	print("--- Reproducing Diplomacy Tab Click ---")
	var main_scene = load("res://scenes/Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	
	print("Main added to tree, calling show_diplomacy_menu('civ')...")
	main.hud.show_diplomacy_menu("civ")
	print("show_diplomacy_menu('civ') finished without crash!")
	
	print("Testing espionage tab...")
	main.hud.show_diplomacy_menu("espionage")
	print("show_diplomacy_menu('espionage') finished without crash!")
	
	main.queue_free()
	quit(0)
