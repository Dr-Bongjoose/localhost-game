extends SceneTree
# JOO-24 layout probe v2: force the real Pixel 11 Pro landscape window size
# (2410x1080) BEFORE the scene loads, then report engine-computed rects +
# final-transform physical coordinates for the nodes the device leg must tap.
# Run: godot --headless --path . --script scripts/test_layout_probe.gd

func _init() -> void:
	# Set window size before anything loads; headless honours these for layout.
	root.size = Vector2i(2410, 1080)
	root.content_scale_factor = 1.0
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	for i in range(8):
		await process_frame
	print("WINDOW_SIZE=", root.size)
	print("CONTENT_SCALE_SIZE=", root.content_scale_size)
	var ft: Transform2D = root.get_final_transform()
	print("FINAL_TRANSFORM=", ft)
	print("VISIBLE_RECT=", root.get_visible_rect().size)
	var names := [
		"ScrollContainer/MarginContainer/VBox/TabBar/TabContainment",
		"ScrollContainer/MarginContainer/VBox/TabBar/TabCodex",
		"ScrollContainer/MarginContainer/VBox/TabBar/TabZones",
		"ScrollContainer/MarginContainer/VBox/StatusBar",
		"ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/ParentBDropdown",
		"ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedButton",
		"ScrollContainer/MarginContainer/VBox/ContainmentView/HomeBasePanel/RecallDefenderButton",
		"ScrollContainer/MarginContainer/VBox/ZonesView/ZoneDeployPanel/DeployDropdown",
		"ScrollContainer/MarginContainer/VBox/ZonesView/ZoneDeployPanel/DeployButton",
		"ScrollContainer/MarginContainer/VBox/ZonesView/ZoneDeployPanel/RecallButton",
	]
	for n in names:
		var node = main.get_node_or_null(n)
		if node == null:
			print("MISSING ", n)
			continue
		var r: Rect2 = node.get_global_rect()
		var tl: Vector2 = ft * r.position
		var br: Vector2 = ft * (r.position + r.size)
		print("RECT %s canvas=(%.0f,%.0f)-(%.0f,%.0f) physical=(%.0f,%.0f)-(%.0f,%.0f) visible=%s" % [
			n.get_file(), r.position.x, r.position.y, r.end.x, r.end.y,
			tl.x, tl.y, br.x, br.y, node.is_visible_in_tree()])
	var sc: ScrollContainer = main.get_node("ScrollContainer")
	print("SCROLL_VERTICAL=", sc.scroll_vertical)
	print("LAYOUT_PROBE_DONE")
	quit(0)