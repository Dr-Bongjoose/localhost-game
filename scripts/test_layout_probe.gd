extends SceneTree
# JOO-24 layout probe v3: run under xvfb with a REAL physical window size via
# the Godot CLI flag --resolution WxH (root.size is overridden by the project
# base size if set from script, so the CLI flag is the only reliable way).
# Reports engine-computed canvas rects + final-transform physical coordinates
# for every node the device leg taps, plus the live ExitConfirmDialog geometry.
# Usage: xvfb-run godot --path . --resolution 2410x1080 --script scripts/test_layout_probe.gd
# Canvas constants here are device-independent: stretch mode canvas_items +
# aspect expand pins canvas Y to 1280 in landscape; scale = dev_h / 1280.

func _init() -> void:
	print("WINDOW_SIZE=", root.size)
	print("CONTENT_SCALE_SIZE=", root.content_scale_size)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	for i in range(8):
		await process_frame
	var ft: Transform2D = root.get_final_transform()
	print("FINAL_TRANSFORM=", ft)
	print("VISIBLE_RECT=", root.get_visible_rect().size)
	var names := [
		"ScrollContainer/MarginContainer/VBox/TabBar/TabContainment",
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
	# Trigger the BACK-key confirm dialog and probe its live window + buttons.
	main._show_exit_confirm()
	for i in range(8):
		await process_frame
	var dlg: ConfirmationDialog = null
	for c in root.get_children():
		if c is ConfirmationDialog:
			dlg = c
			break
	if dlg == null:
		print("EXIT_DIALOG=MISSING")
	else:
		print("EXIT_DIALOG title=", dlg.title, " visible=", dlg.visible,
			" pos=", dlg.position, " size=", dlg.size)
		for pair in [["OK(Quit)", dlg.get_ok_button()], ["CANCEL(KeepPlaying)", dlg.get_cancel_button()]]:
			var lbl: String = pair[0]
			var b: Button = pair[1]
			if b == null or not b.is_visible_in_tree():
				print("EXIT_BTN %s MISSING_OR_HIDDEN" % lbl)
				continue
			# Popup-local rect: canvas coord = dlg.position + local position.
			var gr: Rect2 = b.get_global_rect()
			var c_tl: Vector2 = Vector2(dlg.position) + gr.position
			var c_br: Vector2 = Vector2(dlg.position) + gr.end
			print("EXIT_BTN %s local=(%.0f,%.0f)-(%.0f,%.0f) canvas=(%.0f,%.0f)-(%.0f,%.0f)" % [
				lbl, gr.position.x, gr.position.y, gr.end.x, gr.end.y, c_tl.x, c_tl.y, c_br.x, c_br.y])
		dlg.queue_free()
	print("LAYOUT_PROBE_DONE")
	quit(0)