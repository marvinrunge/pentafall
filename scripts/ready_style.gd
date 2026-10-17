extends RefCounted
## How "ready" looks wherever a ready check is shown: the lobby and Upkeep. Preloaded by
## path, like IconStyle.
##
## It used to be a word in a list - "READY" or "not ready" in two greys that were hard to
## tell apart - so nobody could see at a glance who the team was waiting for. Now it is a
## filled chip per player, green when they are ready and amber when they are not, and the
## player's own ready button wears the same two colours.

const READY_COLOR := Color(0.24, 0.72, 0.32)
const WAITING_COLOR := Color(0.93, 0.62, 0.16)


static func color(ready: bool) -> Color:
	return READY_COLOR if ready else WAITING_COLOR


## One player's line: their name and their state on a chip in the state's colour.
static func row(player_name: String, ready: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	var tint: Color = color(ready)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.22)
	style.border_color = tint
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	chip.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	chip.add_child(line)
	var name_label := Label.new()
	name_label.text = player_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	line.add_child(name_label)
	var state := Label.new()
	state.text = "READY" if ready else "NOT READY"
	state.add_theme_color_override("font_color", tint.lightened(0.25))
	line.add_child(state)
	return chip


## The local ready button: green and filled once this player is ready, amber until then.
static func style_button(button: Button, ready: bool) -> void:
	var tint: Color = color(ready)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		var fill: float = 0.85 if ready else 0.28
		if state == "hover" or state == "focus":
			fill += 0.1
		elif state == "disabled":
			fill = 0.12
		style.bg_color = Color(tint.r, tint.g, tint.b, fill)
		style.border_color = tint.lightened(0.35) if state == "focus" else tint
		style.set_border_width_all(3 if state == "focus" else 2)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, style)
	var text_color: Color = Color(0.05, 0.08, 0.05) if ready else Color(1.0, 0.9, 0.7)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, text_color)
