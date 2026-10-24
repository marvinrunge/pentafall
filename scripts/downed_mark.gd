class_name DownedMark
extends RefCounted
## The mark of a teammate who is down and waiting to be picked up (docs/REVIVE_PLAN.md): a
## white-edged red cross that pulses, and round it the time they have left, emptying from twelve
## o'clock. The minimap draws it where they lie and TeamFrames on their head, the same mark in
## both places so one is recognised from the other.
##
## Revives never happened in play: nobody saw where the teammate was lying, and the frame on the
## left only greyed a little. Drawing is all this is - nothing about being down changes.

const CROSS_COLOR := Color(0.95, 0.15, 0.12)
const EDGE_COLOR := Color(1.0, 1.0, 1.0)
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const PULSE_HZ := 1.6


## 0..1, the same on every caller in the same frame so the two marks pulse together.
static func pulse() -> float:
	return 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * TAU * PULSE_HZ)


## A cross `half` wide either side of `centre`, brightening and swelling a little with the pulse.
static func draw_cross(canvas: CanvasItem, centre: Vector2, half: float, alpha: float = 1.0) -> void:
	var beat: float = pulse()
	var h: float = half * (0.9 + 0.15 * beat)
	var arm: float = h * 0.36
	var edge: float = maxf(1.0, h * 0.18)
	var edge_color := Color(EDGE_COLOR, alpha)
	canvas.draw_rect(Rect2(centre.x - arm - edge, centre.y - h - edge, (arm + edge) * 2.0, (h + edge) * 2.0), edge_color)
	canvas.draw_rect(Rect2(centre.x - h - edge, centre.y - arm - edge, (h + edge) * 2.0, (arm + edge) * 2.0), edge_color)
	var cross_color := Color(CROSS_COLOR.lerp(Color(1.0, 0.45, 0.4), beat), alpha)
	canvas.draw_rect(Rect2(centre.x - arm, centre.y - h, arm * 2.0, h * 2.0), cross_color)
	canvas.draw_rect(Rect2(centre.x - h, centre.y - arm, h * 2.0, arm * 2.0), cross_color)


## The countdown round it: `share` of a full circle left, from twelve o'clock clockwise.
static func draw_countdown(canvas: CanvasItem, centre: Vector2, radius: float, share: float, width: float = 1.5) -> void:
	canvas.draw_arc(centre, radius, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.55), width + 1.0)
	if share <= 0.0:
		return
	var start: float = -PI * 0.5
	canvas.draw_arc(centre, radius, start, start + TAU * clampf(share, 0.0, 1.0), maxi(6, int(32.0 * share)), RING_COLOR, width)


## How much of a downed player's time is left, 0..1.
static func share_left(player: Object) -> float:
	var total_value: Variant = player.get("down_total")
	var total: float = float(total_value) if total_value != null else 0.0
	if total <= 0.0:
		return 0.0
	return clampf(float(player.get("down_timer")) / total, 0.0, 1.0)
