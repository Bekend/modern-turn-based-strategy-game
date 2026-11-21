extends SceneTree

func _init() -> void:
	print("--- Testing Scene Instantiation & Processing ---")
	
	# 1. Test MainMenu scene
	print("Instantiating MainMenu...")
	var menu_scene: PackedScene = load("res://scenes/MainMenu.tscn")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	print("MainMenu instantiated successfully.")
	menu.queue_free()
	
	# 2. Test Main scene
	print("Instantiating Main...")
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	print("Main game scene instantiated and initialized successfully.")
	main_node.queue_free()
	
	print("--- SCENE LOAD VERIFICATION COMPLETE: ZERO CRASHES ---")
	quit(0)
