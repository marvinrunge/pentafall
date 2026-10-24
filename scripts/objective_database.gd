class_name ObjectiveDatabase
extends RefCounted
## The first-steps objectives (docs/ONBOARDING_PLAN.md): what a new player is walked through,
## in order, by ObjectiveTracker above the minimap.
##
## In a duo test the experienced player had to say all of this out loud - the crystal is also
## the myr workshop, the wells can be worked by hand, Upkeep is where the mana goes. This is
## that voice. Each one is done by the LOCAL player's own action (SignalBus.objective_progress),
## so a veteran building every myr never ticks a newcomer's list.
##
##   id                the id raised with SignalBus.objective_progress, and kept in
##                     UserSettings.objectives_done once finished
##   text              the objective
##   hint              how, in smaller type; "{interact}" and friends are the key for that
##                     action on the device in use (InputHint.key)
##   multiplayer_only  shown only in a run with somebody else in it

const InputHint := preload("res://scripts/input_hint.gd")

const OBJECTIVES: Array[Dictionary] = [
	{"id": "build_myr", "text": "Build a myr",
		"hint": "Walk to the crystal and press {interact}"},
	{"id": "assign_myr", "text": "Send a myr to a mana well",
		"hint": "At the crystal, pick a lane for it"},
	{"id": "harvest_by_hand", "text": "Bring mana home yourself",
		"hint": "Hold {interact} at a mana well, then carry it to the crystal"},
	{"id": "spend_skill_point", "text": "Spend a skill point",
		"hint": "Open the skill tree with {skill_tree}"},
	{"id": "level_myr", "text": "Level up a myr",
		"hint": "At the crystal, beside its name"},
	{"id": "upkeep_purchase", "text": "Buy something at Upkeep",
		"hint": "Between waves, in the Upkeep panel"},
	{"id": "build_guard", "text": "Build a guard myr",
		"hint": "At the crystal: an Enforcer or a Lodestone"},
	{"id": "revive_teammate", "text": "Revive a teammate",
		"hint": "Stand by a downed teammate and hold still on {interact}",
		"multiplayer_only": true},
]


static func has_objective(objective_id: String) -> bool:
	for objective: Dictionary in OBJECTIVES:
		if String(objective["id"]) == objective_id:
			return true
	return false


## The hint with its keys filled in for the device in use.
static func hint_for(objective: Dictionary) -> String:
	var hint: String = String(objective.get("hint", ""))
	for action: String in ["interact", "skill_tree"]:
		hint = hint.replace("{%s}" % action, InputHint.key(action))
	return hint
