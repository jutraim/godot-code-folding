@tool
extends EditorPlugin

var grid_menu_button: Button
var grid_popup: PopupPanel
var grid: GridContainer

const FOLD = preload("uid://djb8crtxxv5ev")
const UNFOLD = preload("uid://dq1ahvop1olpr")

enum GridAction {
	COLLAPSE_ALL, UNFOLD_ALL,
	COLLAPSE_ONLY_REGIONS, UNFOLD_ONLY_REGIONS,
	COLLAPSE_REGIONS, UNFOLD_REGIONS,
	COLLAPSE_CODE, UNFOLD_CODE,
	COLLAPSE_COMMENTS, UNFOLD_COMMENTS,
}

var preview_highlight_color: Color
var currently_highlighted_lines: Array[int] = []

var folding := false

var settings

var action_setup = []

func _initialize_action_setup():
	action_setup = [
		{
			"category_text": "All",
			"collapse_action": GridAction.COLLAPSE_ALL,
			"unfold_action": GridAction.UNFOLD_ALL,
			"color": settings.get_setting("text_editor/theme/highlighting/symbol_color")
		},
		{
			"category_text": "Regions (Markers)",
			"collapse_action": GridAction.COLLAPSE_ONLY_REGIONS,
			"unfold_action": GridAction.UNFOLD_ONLY_REGIONS,
			"color": settings.get_setting("text_editor/theme/highlighting/control_flow_keyword_color")
		},
		{
			"category_text": "In Regions (Content)",
			"collapse_action": GridAction.COLLAPSE_REGIONS,
			"unfold_action": GridAction.UNFOLD_REGIONS,
			"color": settings.get_setting("text_editor/theme/highlighting/keyword_color")
		},
		{
			"category_text": "Code",
			"collapse_action": GridAction.COLLAPSE_CODE,
			"unfold_action": GridAction.UNFOLD_CODE,
			"color": settings.get_setting("text_editor/theme/highlighting/function_color")
		},
		{
			"category_text": "Comments",
			"collapse_action": GridAction.COLLAPSE_COMMENTS,
			"unfold_action": GridAction.UNFOLD_COMMENTS,
			"color": settings.get_setting("text_editor/theme/highlighting/comment_color")
		}
	]

func _enter_tree():
	settings = EditorInterface.get_editor_settings()
	_initialize_action_setup()

	if EditorInterface.get_editor_theme():
		var accent_color = EditorInterface.get_editor_theme().get_color("accent_color", "Editor")
		preview_highlight_color = accent_color * Color(1,1,1,0.3)
	else:
		preview_highlight_color = Color(0.5, 0.5, 0.0, 0.3)

	grid_menu_button = Button.new()
	grid_menu_button.toggle_mode = true
	grid_menu_button.flat = true
	grid_menu_button.text = "Folding"
	grid_menu_button.pressed.connect(_on_show_grid_popup)

	grid_popup = PopupPanel.new()
	grid_popup.visibility_changed.connect(_on_popup_visibility_changed)

	var local_grid = GridContainer.new()
	local_grid.columns = 3
	grid = local_grid
	grid_popup.add_child(local_grid)

	for item_setup in action_setup:

		var collapse_button = Button.new()

		collapse_button.icon = FOLD

		collapse_button.flat = true
		collapse_button.self_modulate = item_setup.color
		collapse_button.tooltip_text = "Collapse " + item_setup.category_text
		collapse_button.pressed.connect(_on_grid_action_pressed.bind(item_setup.collapse_action))
		collapse_button.mouse_entered.connect(_on_button_mouse_entered.bind(item_setup.collapse_action, item_setup.color if item_setup.color is Color else Color.WHITE))
		collapse_button.mouse_exited.connect(_clear_all_preview_highlights)
		local_grid.add_child(collapse_button)

		var unfold_button = Button.new()

		unfold_button.icon = UNFOLD

		unfold_button.flat = true
		unfold_button.self_modulate = item_setup.color
		unfold_button.tooltip_text = "Unfold " + item_setup.category_text
		unfold_button.pressed.connect(_on_grid_action_pressed.bind(item_setup.unfold_action))
		unfold_button.mouse_entered.connect(_on_button_mouse_entered.bind(item_setup.unfold_action, item_setup.color if item_setup.color is Color else Color.WHITE))
		unfold_button.mouse_exited.connect(_clear_all_preview_highlights)
		local_grid.add_child(unfold_button)

		var label = Label.new()
		label.text = item_setup.category_text
		if item_setup.color is Color:
			label.self_modulate = item_setup.color
		else:
			label.self_modulate = Color.WHITE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		local_grid.add_child(label)

		item_setup["label_node"] = label
		item_setup["collapse_button_node"] = collapse_button
		item_setup["unfold_button_node"] = unfold_button

	grid_menu_button.add_child(grid_popup)

	var toolbar = EditorInterface.get_script_editor().get_child(0).get_child(0)
	toolbar.add_child(grid_menu_button)
	if toolbar.get_child_count() > 28 && toolbar.get_child(28):
		toolbar.move_child(grid_menu_button, 28)
	else:
		grid_menu_button.move_to_front()

	var cur_editor = EditorInterface.get_script_editor()
	cur_editor.editor_script_changed.connect(func(script):
		var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
		if editor is CodeEdit and not editor.gutter_clicked.is_connected(do_stuff):
			editor.gutter_clicked.connect(do_stuff)
	)
	cur_editor.script_close.connect(func(script):
		var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
		if editor is CodeEdit and editor.gutter_clicked.is_connected(do_stuff):
			editor.gutter_clicked.disconnect(do_stuff)
	)

func _exit_tree() -> void:
	if grid_menu_button:
		grid_menu_button.queue_free()

func _on_show_grid_popup():
	_refresh_popup_state()

	var button_rect = grid_menu_button.get_global_rect()
	var actual_grid = grid_popup.get_child(0) if grid_popup.get_child_count() > 0 else null
	if actual_grid is GridContainer:
		grid_popup.popup(Rect2i(Vector2i(button_rect.position.x, button_rect.end.y), Vector2i.ZERO))
		var tween = grid_popup.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CIRC)
		var stylebox = grid_popup.get_theme_stylebox("panel", "PopupPanel")
		var margins = stylebox.get_minimum_size().y
		var target_height = actual_grid.get_combined_minimum_size().y + margins
		grid_popup.max_size.y = 0
		tween.tween_property(grid_popup, "max_size:y", target_height, 0.2).from(0)
		grid_popup.max_size.x = actual_grid.get_combined_minimum_size().x + stylebox.get_minimum_size().x
		grid_popup.size.x = grid_popup.max_size.x
	else:
		grid_popup.popup(Rect2i(Vector2i(button_rect.position.x, button_rect.end.y), Vector2i(150,100)))

func _script_has_regions(editor: CodeEdit) -> bool:
	for i in range(editor.get_line_count()):
		if editor.is_line_code_region_start(i):
			return true
	return false

func _on_popup_visibility_changed():
	if not grid_popup.visible:
		_clear_all_preview_highlights()

func _on_button_mouse_entered(action_id: GridAction, category_color: Color):
	_clear_all_preview_highlights()
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not (editor is CodeEdit): return

	currently_highlighted_lines = _get_lines_to_highlight(editor, action_id)
	var final_highlight_color = preview_highlight_color * category_color
	for line_idx in currently_highlighted_lines:
		editor.set_line_background_color(line_idx, final_highlight_color)

func _clear_all_preview_highlights():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if editor is CodeEdit:
		for line_idx in currently_highlighted_lines:
			editor.set_line_background_color(line_idx, Color(0,0,0,0))

			if editor.is_line_code_region_start(line_idx) and editor.is_line_folded(line_idx):
				editor.set_line_background_color(line_idx, editor.get_theme_color("folded_code_region_color"))

	currently_highlighted_lines.clear()

func _get_lines_to_highlight(editor: CodeEdit, action_id: GridAction) -> Array[int]:
	match action_id:
		GridAction.COLLAPSE_ALL: return _get_lines_for_collapse_all(editor)
		GridAction.UNFOLD_ALL: return _get_lines_for_unfold_all(editor)
		GridAction.COLLAPSE_ONLY_REGIONS: return _get_lines_for_collapse_only_regions(editor)
		GridAction.UNFOLD_ONLY_REGIONS: return _get_lines_for_unfold_only_regions(editor)
		GridAction.COLLAPSE_REGIONS: return _get_lines_for_collapse_in_regions(editor)
		GridAction.UNFOLD_REGIONS: return _get_lines_for_unfold_in_regions(editor)
		GridAction.COLLAPSE_CODE: return _get_lines_for_collapse_code(editor)
		GridAction.UNFOLD_CODE: return _get_lines_for_unfold_code(editor)
		GridAction.COLLAPSE_COMMENTS: return _get_lines_for_collapse_comments(editor)
		GridAction.UNFOLD_COMMENTS: return _get_lines_for_unfold_comments(editor)
	return []

func _is_line_comment(editor: CodeEdit, line_idx: int) -> bool:
	if line_idx < 0 or line_idx >= editor.get_line_count(): return false
	return editor.get_line(line_idx).strip_edges(true, true).begins_with("#")

func _get_lines_for_collapse_all(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	for i in range(editor.get_line_count()):
		if editor.can_fold_line(i) and not editor.is_line_folded(i):
			lines.append(i)
	return lines

func _get_lines_for_unfold_all(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	for i in range(editor.get_line_count()):
		if editor.is_line_folded(i):
			lines.append(i)
	return lines

func _get_lines_for_collapse_only_regions(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	for i in range(editor.get_line_count()):
		if editor.is_line_code_region_start(i) and editor.can_fold_line(i) and not editor.is_line_folded(i):
			lines.append(i)
	return lines

func _get_lines_for_unfold_only_regions(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	for i in range(editor.get_line_count()):
		if editor.is_line_code_region_start(i) and editor.is_line_folded(i):
			lines.append(i)
	return lines

func _get_lines_for_collapse_in_regions(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	var depth := 0
	for i in range(editor.get_line_count()):
		if editor.is_line_code_region_start(i):
			depth += 1
			continue
		if editor.is_line_code_region_end(i):
			if depth > 0: depth -= 1
			continue
		if depth > 0 and editor.can_fold_line(i) and not editor.is_line_folded(i):
			lines.append(i)
	return lines

func _get_lines_for_unfold_in_regions(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	var line_count := editor.get_line_count()
	var depth := 0
	for i in range(line_count):
		var is_start := editor.is_line_code_region_start(i)
		var is_end := editor.is_line_code_region_end(i)
		if is_start:
			depth += 1
		elif is_end:
			if depth > 0: depth -= 1
		elif depth > 0:
			if editor.is_line_folded(i):
				lines.append(i)
	var unique_lines: Array[int] = []
	for line_num in lines:
		if not unique_lines.has(line_num): unique_lines.append(line_num)
	return unique_lines

func _get_lines_for_collapse_code(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	for i in range(editor.get_line_count()):
		if not _is_line_comment(editor, i) and editor.can_fold_line(i) and not editor.is_line_folded(i):
			lines.append(i)
	return lines

func _get_lines_for_unfold_code(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	for i in range(editor.get_line_count()):
		if not _is_line_comment(editor, i) and editor.is_line_folded(i):
			lines.append(i)
	return lines

func _get_lines_for_collapse_comments(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	for i in range(editor.get_line_count()):
		if _is_line_comment(editor, i) and editor.can_fold_line(i) and not editor.is_line_folded(i) and not editor.is_line_code_region_start(i):
			lines.append(i)
	return lines

func _get_lines_for_unfold_comments(editor: CodeEdit) -> Array[int]:
	var lines: Array[int] = []
	for i in range(editor.get_line_count()):
		if _is_line_comment(editor, i) and editor.is_line_folded(i) and not editor.is_line_code_region_start(i):
			lines.append(i)
	return lines

func _on_grid_action_pressed(action_id: GridAction):
	_clear_all_preview_highlights()

	match action_id:
		GridAction.COLLAPSE_ALL: fold_all()
		GridAction.UNFOLD_ALL: unfold_all()
		GridAction.COLLAPSE_ONLY_REGIONS: fold_only_regions()
		GridAction.UNFOLD_ONLY_REGIONS: unfold_only_regions()
		GridAction.COLLAPSE_REGIONS: fold_inside_regions()
		GridAction.UNFOLD_REGIONS: unfold_inside_regions()
		GridAction.COLLAPSE_CODE: fold_code_only()
		GridAction.UNFOLD_CODE: unfold_code_only()
		GridAction.COLLAPSE_COMMENTS: fold_comments_only()
		GridAction.UNFOLD_COMMENTS: unfold_comments_only()

	_refresh_popup_state()

func fold_all():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if editor is CodeEdit: editor.fold_all_lines()

func unfold_all():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if editor is CodeEdit: editor.unfold_all_lines()

func fold_only_regions():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not (editor is CodeEdit): return
	for i in range(editor.get_line_count()):
		if editor.is_line_code_region_start(i) and not editor.is_line_folded(i):
			editor.fold_line(i)

func unfold_only_regions():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not (editor is CodeEdit): return
	for i in range(editor.get_line_count()):
		if editor.is_line_code_region_start(i) and editor.is_line_folded(i):
			editor.unfold_line(i)

func fold_inside_regions():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not (editor is CodeEdit): return
	var depth := 0
	for i in range(editor.get_line_count()):
		if _is_inside_folded_region(editor, i): continue
		if editor.is_line_code_region_start(i): depth += 1; continue
		if editor.is_line_code_region_end(i):
			if depth > 0: depth = max(depth - 1, 0)
			continue
		if depth > 0 and not editor.is_line_folded(i) and editor.can_fold_line(i):
			editor.fold_line(i)

func unfold_inside_regions():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not (editor is CodeEdit): return
	var line_count = editor.get_line_count()
	var depth := 0
	for i in range(line_count):
		if editor.is_line_code_region_start(i): depth += 1; continue
		if editor.is_line_code_region_end(i):
			if depth > 0: depth = max(depth - 1, 0)
			continue
		if depth > 0 and editor.is_line_folded(i):
			editor.unfold_line(i)

func fold_code_only():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not (editor is CodeEdit): return
	for i in range(editor.get_line_count()):
		if not _is_line_comment(editor, i) and editor.can_fold_line(i) and not editor.is_line_folded(i):
			editor.fold_line(i)

func unfold_code_only():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not (editor is CodeEdit): return
	for i in range(editor.get_line_count()):
		if not _is_line_comment(editor, i) and editor.is_line_folded(i):
			editor.unfold_line(i)

func fold_comments_only():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not (editor is CodeEdit): return
	for i in range(editor.get_line_count()):
		if _is_line_comment(editor, i) and editor.can_fold_line(i) and not editor.is_line_folded(i) and not editor.is_line_code_region_start(i):
			editor.fold_line(i)

func unfold_comments_only():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not (editor is CodeEdit): return
	for i in range(editor.get_line_count()):
		if _is_line_comment(editor, i) and editor.is_line_folded(i) and not editor.is_line_code_region_start(i):
			editor.unfold_line(i)

func do_stuff(line: int, gutter: int):
	if gutter == 1:
		var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
		if not (editor is CodeEdit): return
		if editor.is_line_code_region_start(line):
			if editor.is_line_folded(line):
				editor.unfold_line(line)
				editor.set_line_gutter_icon(line, gutter, EditorInterface.get_editor_theme().get_icon("GuiTreeArrowDown", "EditorIcons"))
			else:
				editor.fold_line(line)
				editor.set_line_gutter_icon(line, gutter, EditorInterface.get_editor_theme().get_icon("GuiTreeArrowRight", "EditorIcons"))

func _is_inside_folded_region(editor: CodeEdit, line: int) -> bool:
	var depth := 0
	for j in range(line -1, -1, -1):
		if editor.is_line_code_region_end(j):
			depth += 1
		elif editor.is_line_code_region_start(j):
			if depth == 0:
				return editor.is_line_folded(j)
			depth -= 1
	return false

func _refresh_popup_state():
	var editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if not editor is CodeEdit:

		for item_setup in action_setup:
			item_setup.collapse_button_node.disabled = true
			item_setup.unfold_button_node.disabled = true
		return


	for item_setup in action_setup:
		var collapse_action = item_setup.collapse_action
		var unfold_action = item_setup.unfold_action


		var lines_to_collapse = _get_lines_to_highlight(editor, collapse_action)
		var lines_to_unfold = _get_lines_to_highlight(editor, unfold_action)


		item_setup.collapse_button_node.disabled = lines_to_collapse.is_empty()
		item_setup.unfold_button_node.disabled = lines_to_unfold.is_empty()


		var show_item = true
		match item_setup.category_text:
			"Regions (Markers)", "In Regions (Content)":
				show_item = _script_has_regions(editor)
			"Comments":
				show_item = not _get_lines_for_collapse_comments(editor).is_empty() or not _get_lines_for_unfold_comments(editor).is_empty()
			"Code":
				show_item = not _get_lines_for_collapse_code(editor).is_empty() or not _get_lines_for_unfold_code(editor).is_empty()

		item_setup.label_node.visible = show_item
		item_setup.collapse_button_node.visible = show_item
		item_setup.unfold_button_node.visible = show_item
