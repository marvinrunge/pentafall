extends RefCounted
## What the round-two spells that are neither a charge nor a tower DO (docs/SKILL_DESIGN.md,
## "Idea backlog - round two"). The charges are ChargedHits'; the towers are scripts/tower.gd.
## Same shape as SpellEffects: static, no state between casts, the caster passed in - and
## reached the same way, from Player._run_spell_effect on the server.
##
## Preloaded by path rather than given a `class_name`: see scripts/icon_style.gd.

## The ground and nothing else (project.godot's layer 5), like SpellEffects.ENVIRONMENT_MASK.
const ENVIRONMENT_MASK: int = 1 << 4
## Spells Fork casts a second time: the ones that are AIMED at a place or an enemy. A spell
## centred on the caster, a buff or a movement would only do the same thing twice in one spot.
const FORKABLE: Array[String] = [
	"red_1", "red_3", "red_5", "red_6", "black_1", "black_2", "black_4", "blue_4", "blue_11",
	"white_11",
]


## The server half of every round-two spell this file holds.
static func cast(caster: Player, spell_id: String) -> void:
	match spell_id:
		"white_6": _glorious_charge_sweep(caster)
		"white_10": worship(caster)
		"white_11": banishing_light(caster)
		"blue_6": mirror_image(caster)
		"blue_10": counterspell(caster)
		"blue_11": curse_of_the_swine(caster)
		"black_6": _self_buff(caster, spell_id)
		"black_9": animate_dead(caster)
		"black_10": gravewalk(caster)
		"black_11": demonic_pact(caster)
		"red_6": fling(caster)
		"red_7": _self_buff(caster, spell_id)
		"red_9": grapeshot(caster)
		"red_10": fork(caster)
		"green_8": kraul_harpooner(caster)
		"green_9": awaken(caster)
		"green_10": _overrun_sweep(caster)
		"green_11": call_of_the_herd(caster)
	caster._play_sound(SpellEffects.cast_sound(spell_id), caster.global_position)


## The launch half of the two charges that move the caster, run on the caster's own machine
## when the cast STARTS (Player._begin_cast), the way Fire Dash's is: by the release frame the
## body has to be on its way already. Fire Dash's own clock carries it - with no fire behind.
static func launch(caster: Player, spell_id: String) -> void:
	var distance: float = GameSettings.spell_white_charge_distance
	var duration: float = GameSettings.spell_white_charge_duration
	if spell_id == "green_10":
		distance = GameSettings.spell_green_overrun_distance
		duration = GameSettings.spell_green_overrun_duration
		caster._overrun_timer = duration + 0.3
	var forward: Vector3 = -caster.transform.basis.z
	forward.y = 0.0
	caster.velocity = forward.normalized() * distance * caster._rank_area() / maxf(duration, 0.05)
	caster.velocity.y = 0.0
	caster._dash_timer = duration
	caster._dash_trail_timer = 0.0
	caster._dash_trail_radius = 0.0
	caster._spawn_spell_fx(spell_id, caster.global_position, 1.0)


# --- WHITE ----------------------------------------------------------------------------------

## Glorious Charge, the release half: everything the charge went through, from where it
## started to just ahead of where it is now, is carried on and stunned; every ally on the way
## is shielded.
static func _glorious_charge_sweep(caster: Player) -> void:
	var forward: Vector3 = _flat_forward(caster)
	var length: float = GameSettings.spell_white_charge_distance * caster._rank_area()
	var damage: float = GameSettings.spell_white_charge_damage * caster._rank_damage() * caster.get_spell_damage_multiplier()
	for enemy: Node3D in _in_path(caster, forward, length, GameSettings.spell_white_charge_width):
		caster._deal_damage(enemy, damage, true)
		if enemy is EnemyBase and is_instance_valid(enemy):
			(enemy as EnemyBase).apply_knockback(forward * 14.0)
			if not (enemy as EnemyBase).is_immune_to_control():
				(enemy as EnemyBase).apply_stun(GameSettings.spell_white_charge_stun)
	var shield: float = GameSettings.spell_white_charge_shield * caster._rank_damage()
	for node: Node in caster.get_tree().get_nodes_in_group("player"):
		var ally := node as Node3D
		if ally == null or not ally.has_method("grant_protection_shield"):
			continue
		if _distance_to_path(caster, forward, length, ally.global_position) <= GameSettings.spell_white_charge_width:
			ally.grant_protection_shield(shield, GameSettings.spell_white_charge_shield_duration)
	caster._shake(0.25, 0.2)


## Worship: hallowed ground round the caster. While allies and myrs stand in it nothing brings
## them below 1 health - Player.take_damage and Myr.take_damage ask `protects`.
static func worship(caster: Player) -> void:
	var radius: float = GameSettings.spell_white_worship_radius * caster._rank_area()
	var duration: float = GameSettings.spell_white_worship_duration * caster._rank_duration()
	_worship_zones.append({"at": caster.global_position, "radius": radius, "until": _now() + duration})
	caster._spawn_spell_fx("white_10", caster.global_position, radius)


static var _worship_zones: Array = []


## Whether `at` stands on hallowed ground right now (server).
static func protects(at: Vector3) -> bool:
	var now: float = _now()
	for i: int in range(_worship_zones.size() - 1, -1, -1):
		var zone: Dictionary = _worship_zones[i]
		if float(zone["until"]) <= now:
			_worship_zones.remove_at(i)
			continue
		if Vector2(at.x - zone["at"].x, at.z - zone["at"].z).length() <= float(zone["radius"]):
			return true
	return false


static func banishing_light(caster: Player) -> void:
	var at: Vector3 = caster._ground_snap(caster._aim_point(GameSettings.spell_white_banish_range * caster._rank_area()))
	var radius: float = GameSettings.spell_white_banish_radius * caster._rank_area()
	var duration: float = GameSettings.spell_white_banish_duration * caster._rank_duration()
	for enemy: Node3D in caster._enemies_in_radius(at, radius):
		if enemy is EnemyBase:
			(enemy as EnemyBase).banish(duration)
	caster._spawn_spell_fx("white_11", at, radius)


# --- BLUE -----------------------------------------------------------------------------------

## Mirror Image: copies in the caster's own class visual that fight with their class's attack at
## a share of its damage. A copy of an archer or a mage strikes from range.
static func mirror_image(caster: Player) -> void:
	var count: int = GameSettings.rank_count(GameSettings.spell_blue_mirror_count, GameSettings.spell_blue_mirror_count_max, caster._casting_rank)
	var ranged: bool = ClassDatabase.get_class_data(caster.character_class).get("kit", "") in ["bow", "bolt"]
	var hit: float = GameSettings.spell_melee_damage * GameSettings.spell_blue_mirror_damage_share * caster.get_spell_damage_multiplier() * caster._rank_damage()
	for i: int in count:
		var angle: float = TAU * float(i) / float(count) + PI * 0.5
		var at: Vector3 = caster._ground_snap(caster.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.8)
		caster._place_networked({
			"kind": "mirror", "position": at, "yaw": caster.rotation.y,
			"hp": GameSettings.spell_blue_mirror_health * caster._rank_damage(),
			"duration": GameSettings.spell_blue_mirror_duration * caster._rank_duration(),
			"hit_damage": hit, "class": caster.character_class, "color": caster.path_color(),
			"range": 12.0 if ranged else 1.8,
		})
		caster._spawn_spell_fx("blue_6", at, 1.0)


## Counterspell: the special a boss or a miniboss near the caster is winding up fizzles.
static func counterspell(caster: Player) -> void:
	var range_units: float = GameSettings.spell_blue_counterspell_range * caster._rank_area()
	var countered: bool = false
	for enemy: Node3D in caster._enemies_in_radius(caster.global_position, range_units):
		var foe := enemy as EnemyBase
		if foe == null or not (foe.is_boss() or foe.is_miniboss or foe.is_beast()):
			continue
		if foe.is_special_interruptible() and foe.interrupt_special(caster):
			countered = true
			caster._spawn_spell_fx("blue_10", foe.global_position, 1.0)
	if not countered:
		caster._notify("Nothing to counter")
	caster._spawn_spell_fx("blue_10", caster.global_position, 1.0)


static func curse_of_the_swine(caster: Player) -> void:
	var at: Vector3 = caster._ground_snap(caster._aim_point(GameSettings.spell_blue_swine_range * caster._rank_area()))
	var radius: float = GameSettings.spell_blue_swine_radius * caster._rank_area()
	var count: int = GameSettings.rank_count(GameSettings.spell_blue_swine_count, GameSettings.spell_blue_swine_count_max, caster._casting_rank)
	var caught: Array[Node3D] = caster._enemies_in_radius(at, radius)
	caught.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	var duration: float = GameSettings.spell_blue_swine_duration * caster._rank_duration()
	for enemy: Node3D in caught:
		if count <= 0:
			break
		var foe := enemy as EnemyBase
		if foe == null or foe.is_immune_to_control():
			continue
		foe.polymorph(duration)
		count -= 1
	caster._spawn_spell_fx("blue_11", at, radius)


# --- BLACK ----------------------------------------------------------------------------------

## Unholy Strength and Blood Frenzy: a window of every attack, armed on the caster's machine
## like a charge (ChargedHits.TRIGGERS).
static func _self_buff(caster: Player, spell_id: String) -> void:
	caster.arm_next_attack(spell_id, caster._casting_rank)
	caster._spawn_spell_fx(spell_id, caster.global_position, 1.0)


## Animate Dead: the corpse of an elite, a miniboss or a boss near the aim rises as the caster's
## own, bigger and harder than a ghoul, until the wave ends.
static func animate_dead(caster: Player) -> void:
	var aim: Vector3 = caster._aim_point(GameSettings.spell_black_animate_range * caster._rank_area())
	var best: EnemyBase = null
	var best_distance: float = GameSettings.spell_black_animate_search * caster._rank_area()
	for corpse: EnemyBase in EnemyBase.corpses():
		if corpse.enemy_data == null:
			continue
		if corpse.elite_modifier == "" and not corpse.is_miniboss and not corpse.is_boss():
			continue
		var distance: float = corpse.global_position.distance_to(aim)
		if distance < best_distance:
			best_distance = distance
			best = corpse
	if best == null:
		caster._notify("No elite corpse there")
		return
	var data: EnemyData = best.enemy_data
	var at: Vector3 = caster._ground_snap(best.global_position)
	var is_boss: bool = best.is_boss()
	EnemyBase.consume_corpse(best)
	caster._place_networked({
		"kind": "raised", "position": at,
		"hp": data.health * GameSettings.spell_black_animate_health_share * caster._rank_damage(),
		"duration": GameSettings.spell_black_animate_duration,
		"hit_damage": GameSettings.spell_black_animate_damage * caster._rank_damage() * caster.get_spell_damage_multiplier(),
		"color": data.color_identity, "class": "Boss" if is_boss else data.enemy_class,
		"scale": 1.0 if is_boss else 1.3,
	})
	caster._spawn_spell_fx("black_9", at, 1.0)


## Gravewalk: into the corpse nearest the aim; it bursts as the caster arrives.
static func gravewalk(caster: Player) -> void:
	var range_units: float = GameSettings.spell_black_gravewalk_range * caster._rank_area()
	var aim: Vector3 = caster._aim_point(range_units)
	var best: EnemyBase = null
	var best_distance: float = INF
	for corpse: EnemyBase in EnemyBase.corpses():
		if corpse.global_position.distance_to(caster.global_position) > range_units:
			continue
		var distance: float = corpse.global_position.distance_to(aim)
		if distance < best_distance:
			best_distance = distance
			best = corpse
	if best == null:
		caster._notify("No corpse in reach")
		return
	var at: Vector3 = caster._ground_snap(best.global_position)
	caster._spawn_spell_fx("black_10_from", caster.global_position, 1.0)
	EnemyBase.consume_corpse(best)
	caster.teleport_to(at + Vector3(0.0, 0.2, 0.0))
	var radius: float = GameSettings.spell_black_gravewalk_radius * caster._rank_area()
	var damage: float = GameSettings.spell_black_gravewalk_damage * caster._rank_damage() * caster.get_spell_damage_multiplier()
	for enemy: Node3D in caster._enemies_in_radius(at, radius):
		caster._deal_damage(enemy, damage, false)
	caster._spawn_spell_fx("black_10", at, radius)


## Demonic Pact, the server half: the debt. The cooldowns it clears live on the caster's own
## machine and are cleared there (pact_clear_cooldowns, from Player.execute_spell).
static func demonic_pact(caster: Player) -> void:
	caster._pact_kills_left = GameSettings.spell_black_pact_kills
	caster._pact_timer = GameSettings.rank_fraction(GameSettings.spell_black_pact_window, GameSettings.spell_black_pact_window_max, caster._casting_rank)
	caster._pact_debt = GameSettings.rank_fraction(GameSettings.spell_black_pact_debt, GameSettings.spell_black_pact_debt_max, caster._casting_rank)
	caster._spawn_spell_fx("black_11", caster.global_position, 1.0)
	caster._notify("The demon wants %d kills" % caster._pact_kills_left)


## Every black spell off cooldown but Deathtouch and the Pact itself, on the caster's machine.
static func pact_clear_cooldowns(caster: Player) -> void:
	for spell_id: String in SpellDatabase.spells_of("black"):
		if spell_id == "black_3" or spell_id == "black_11":
			continue
		if caster.spell_cooldown_timers.has(spell_id):
			caster.spell_cooldown_timers[spell_id] = 0.0
	SignalBus.quick_slots_changed.emit()


## The demon collects: a kill counts down the debt; time running out with kills still owed
## takes its share of the caster's life - all of it, if that is what is left. Server only.
static func tick_pact(caster: Player, delta: float) -> void:
	if caster._pact_timer <= 0.0 or (Net.is_active() and not Net.is_server()):
		return
	caster._pact_timer -= delta
	if caster._pact_kills_left <= 0:
		caster._pact_timer = 0.0
		caster._notify("The pact is paid")
		return
	if caster._pact_timer <= 0.0:
		caster._notify("The demon collects")
		NetFx.ring(caster.global_position, Player.FX_BLACK, 2.6)
		caster.lose_life(caster.max_hp * caster._pact_debt, true)


## Undying, from Player.die(): rise again at once, untouchable for a moment, with the dread
## throwing back what stood around - once a wave. True when it caught the fall.
static func try_undying(caster: Player) -> bool:
	var rank: int = caster.get_spell_rank("black_8")
	if rank <= 0 or caster._undying_used:
		return false
	caster._undying_used = true
	caster.hp = caster.max_hp * GameSettings.rank_fraction(GameSettings.spell_black_undying_health, GameSettings.spell_black_undying_health_max, rank)
	caster._emit_health_changed()
	caster._invulnerable_timer = GameSettings.spell_black_undying_invulnerable * GameSettings.rank_duration_mult(rank)
	var radius: float = GameSettings.spell_black_undying_radius
	for enemy: Node3D in caster._enemies_in_radius(caster.global_position, radius):
		var away: Vector3 = enemy.global_position - caster.global_position
		away.y = 0.0
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(away.normalized() * GameSettings.spell_black_undying_knockback)
	caster._spawn_spell_fx("black_8", caster.global_position, radius)
	NetFx.sound(&"spell_undying", caster.global_position)
	caster._notify("Undying")
	return true


# --- RED ------------------------------------------------------------------------------------

static func fling(caster: Player) -> void:
	var target: Node3D = caster.aim_target(GameSettings.spell_red_fling_range * caster._rank_area())
	var foe := target as EnemyBase
	if foe == null or foe.is_boss():
		caster._notify("Nothing to seize")
		return
	var to: Vector3 = caster._ground_snap(caster._aim_point(GameSettings.spell_red_fling_throw_range * caster._rank_area(), ENVIRONMENT_MASK))
	if to.distance_to(foe.global_position) < 2.0:
		to = caster._ground_snap(caster.global_position + _flat_forward(caster) * GameSettings.spell_red_fling_throw_range * 0.6)
	foe.fling(to, GameSettings.spell_red_fling_damage * caster._rank_damage() * caster.get_spell_damage_multiplier(),
		GameSettings.spell_red_fling_radius * caster._rank_area(), caster)
	caster._spawn_spell_fx("red_6", foe.global_position, 1.0)


## Grapeshot: one bolt, and one more for every spell this caster cast in the last few seconds.
static func grapeshot(caster: Player) -> void:
	var now: float = _now()
	var recent: int = 0
	for at: float in caster._cast_log:
		if now - at <= GameSettings.spell_red_grapeshot_window:
			recent += 1
	# The log already holds this cast: every OTHER spell in the window adds one.
	var bolts: int = clampi(recent, 1, GameSettings.spell_red_grapeshot_max)
	var targets: Array[Node3D] = caster._enemies_in_radius(caster.global_position, GameSettings.spell_red_grapeshot_range * caster._rank_area())
	if targets.is_empty():
		return
	targets.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(caster.global_position) < b.global_position.distance_squared_to(caster.global_position))
	var damage: float = GameSettings.spell_red_grapeshot_damage * caster._rank_damage() * caster.get_spell_damage_multiplier()
	var from: Vector3 = caster.global_position + Vector3(0.0, 1.4, 0.0)
	for i: int in bolts:
		var victim: Node3D = targets[i % targets.size()]
		if not is_instance_valid(victim):
			continue
		var to: Vector3 = victim.global_position + Vector3(0.0, 1.0, 0.0)
		caster._spawn_spell_fx("red_9_shot", from, from.distance_to(to), to - from)
		caster._deal_damage(victim, damage, false)
	caster._spawn_spell_fx("red_9", caster.global_position, 1.0)


## Fork: the next aimed spell is cast a second time, at the nearest other enemy.
static func fork(caster: Player) -> void:
	caster._fork_armed = true
	caster._spawn_spell_fx("red_10", caster.global_position, 1.0)


## Run from Player._run_spell_effect after an aimed spell resolved: the copy, aimed at the
## enemy nearest the first target that is not it. Leaves Fork armed for a spell it cannot copy.
static func fork_copy(caster: Player, spell_id: String, charge_pct: float) -> void:
	if not caster._fork_armed or not FORKABLE.has(spell_id):
		return
	caster._fork_armed = false
	# What the first casting was aimed at: the enemy in the sights, or the ground there.
	var nearest_first: Node3D = caster.aim_target(60.0)
	var first: Vector3 = nearest_first.global_position if nearest_first != null else caster._aim_point(60.0, ENVIRONMENT_MASK)
	var second: Node3D = null
	var best: float = GameSettings.spell_red_fork_range
	for enemy: Node3D in caster._enemies_in_radius(first, GameSettings.spell_red_fork_range):
		if enemy == nearest_first:
			continue
		var distance: float = enemy.global_position.distance_to(first)
		if distance < best:
			best = distance
			second = enemy
	if second == null:
		return
	var origin: Vector3 = caster.aim_origin()
	var saved: Array = caster._aim_override
	caster._aim_override = [origin, ((second.global_position + Vector3(0.0, 1.0, 0.0)) - origin).normalized()]
	caster._run_spell_effect(spell_id, charge_pct, false, true)
	caster._aim_override = saved
	NetFx.impact(second.global_position + Vector3(0.0, 1.2, 0.0), Color(1.0, 0.55, 0.2), 0.8)


# --- GREEN ----------------------------------------------------------------------------------

## Kraul Harpooner: a vine to what the crosshair is on. An enemy (not a boss) is dragged to the
## caster; a tree or a standing stone drags the caster to it.
static func kraul_harpooner(caster: Player) -> void:
	var range_units: float = GameSettings.spell_green_harpoon_range * caster._rank_area()
	var from: Vector3 = caster.global_position + Vector3(0.0, 1.3, 0.0)
	# An enemy in the sights first - with the aim assist every targeted spell has (aim_target) -
	# and only then the scenery the crosshair is on.
	var enemy: Node3D = caster.aim_target(range_units)
	if enemy is EnemyBase:
		var reach: Vector3 = enemy.global_position + Vector3(0.0, 1.0, 0.0)
		caster._spawn_spell_fx("green_8_chain", from, from.distance_to(reach), reach - from)
		if (enemy as EnemyBase).is_boss():
			caster._notify("Too big to drag")
			return
		var toward: Vector3 = caster.global_position - enemy.global_position
		toward.y = 0.0
		(enemy as EnemyBase).apply_knockback(toward.normalized() * GameSettings.spell_green_harpoon_pull * minf(toward.length() / 6.0, 2.5))
		return
	var hit: Dictionary = _aim_ray(caster, range_units, ENVIRONMENT_MASK)
	if hit.is_empty():
		caster._notify("Nothing to hook")
		return
	var at: Vector3 = hit["position"]
	caster._spawn_spell_fx("green_8_chain", from, from.distance_to(at), at - from)
	if _scenery_kind(hit["collider"] as Node) == "":
		caster._notify("Hook a tree or a standing stone")
		return
	caster.pull_to(at - (at - caster.global_position).normalized() * 1.2, GameSettings.spell_green_harpoon_self_speed)
	caster._spawn_spell_fx("green_8", caster.global_position, 1.0)


## Awaken: a tree the crosshair is on rises as a treant of its biome; a standing stone of the
## ring as a golem. It fights for a time.
static func awaken(caster: Player) -> void:
	var hit: Dictionary = _aim_ray(caster, GameSettings.spell_green_awaken_range * caster._rank_area(), ENVIRONMENT_MASK)
	var kind: String = _scenery_kind(hit.get("collider") as Node) if not hit.is_empty() else ""
	if kind == "":
		caster._notify("Aim at a tree or a standing stone")
		return
	var at: Vector3 = caster._ground_snap(hit["position"] + (caster.global_position - hit["position"]).normalized() * 1.5)
	caster._place_networked({
		"kind": kind, "position": at,
		"hp": GameSettings.spell_green_awaken_health * caster._rank_damage(),
		"duration": GameSettings.spell_green_awaken_duration * caster._rank_duration(),
		"hit_damage": GameSettings.spell_green_awaken_damage * caster._rank_damage() * caster.get_spell_damage_multiplier(),
		"color": lane_color_at(caster, at),
	})
	caster._spawn_spell_fx("green_9", at, 2.0)


## Overrun, the release half: everything in the charge's path is thrown aside.
static func _overrun_sweep(caster: Player) -> void:
	var forward: Vector3 = _flat_forward(caster)
	var length: float = GameSettings.spell_green_overrun_distance * caster._rank_area()
	caster._overrun_timer = maxf(caster._overrun_timer, 0.5)
	var side: Vector3 = forward.cross(Vector3.UP).normalized()
	for enemy: Node3D in _in_path(caster, forward, length, GameSettings.spell_green_overrun_width):
		if not (enemy is EnemyBase) or (enemy as EnemyBase).is_boss():
			continue
		var offset: Vector3 = enemy.global_position - caster.global_position
		var push: Vector3 = side * (1.0 if offset.dot(side) >= 0.0 else -1.0)
		(enemy as EnemyBase).apply_knockback((push + forward * 0.3).normalized() * GameSettings.spell_green_overrun_knockback * caster._rank_area())
	caster._shake(0.3, 0.25)


## Call of the Herd: spends the trophy taken last and calls that beast, at the size it was
## hunted at, until it falls or the wave ends.
static func call_of_the_herd(caster: Player) -> void:
	if caster.beast_trophies.is_empty():
		caster._notify("Hunt a beast and take its trophy first")
		return
	var trophy: Dictionary = caster.beast_trophies.pop_back()
	caster._publish_trophies()
	var color: String = String(trophy.get("color", "Green"))
	var size: float = float(trophy.get("size", 1.0))
	var at: Vector3 = caster._ground_snap(caster.global_position + _flat_forward(caster) * 2.5)
	var species: Dictionary = EnemyBase.BeastDatabase.species(color)
	caster._place_networked({
		"kind": "beast", "position": at, "yaw": caster.rotation.y,
		"hp": float(species["health"]) * pow(size, 1.3) * caster._rank_damage(),
		"duration": GameSettings.spell_green_herd_duration,
		"hit_damage": float(species["attack_damage"]) * pow(size, 0.7) * caster._rank_damage() * caster.get_spell_damage_multiplier(),
		"color": color, "scale": size,
	})
	caster._spawn_spell_fx("green_11", at, 2.0)


## The biome colour at `at`: the lane whose wedge it is in (WildlifeManager.WEDGE_HALF_DEGREES).
static func lane_color_at(caster: Node, at: Vector3) -> String:
	var scene: Node = caster.get_tree().current_scene
	var names: Variant = scene.get("LANE_NAMES") if scene != null else null
	var spawners: Variant = scene.get("enemy_spawners") if scene != null else null
	if not (names is Array) or not (spawners is Array) or (spawners as Array).is_empty():
		return "Green"
	var best: String = "Green"
	var best_angle: float = INF
	var heading: float = atan2(at.z, at.x)
	for i: int in (spawners as Array).size():
		var spawner := (spawners as Array)[i] as Node3D
		if spawner == null:
			continue
		var angle: float = absf(angle_difference(heading, atan2(spawner.global_position.z, spawner.global_position.x)))
		if angle < best_angle:
			best_angle = angle
			best = String((names as Array)[i])
	return best


# --- helpers --------------------------------------------------------------------------------

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func _flat_forward(caster: Player) -> Vector3:
	var forward: Vector3 = caster.aim_direction()
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -caster.global_basis.z
		forward.y = 0.0
	return forward.normalized()


## Enemies within `width` of the stretch a charge covered: from `length` behind the caster to
## a body's length ahead of them (by the release frame it has mostly run).
static func _in_path(caster: Player, forward: Vector3, length: float, width: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var centre: Vector3 = caster.global_position - forward * length * 0.4
	for enemy: Node3D in caster._enemies_in_radius(centre, length * 0.8 + width):
		if _distance_to_path(caster, forward, length, enemy.global_position) <= width:
			out.append(enemy)
	return out


static func _distance_to_path(caster: Player, forward: Vector3, length: float, at: Vector3) -> float:
	var start: Vector3 = caster.global_position - forward * length
	var end: Vector3 = caster.global_position + forward * 1.5
	var flat_at := Vector3(at.x, 0.0, at.z)
	var a := Vector3(start.x, 0.0, start.z)
	var b := Vector3(end.x, 0.0, end.z)
	var ab: Vector3 = b - a
	var t: float = clampf((flat_at - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return flat_at.distance_to(a + ab * t)


static func _aim_ray(caster: Player, distance: float, mask: int) -> Dictionary:
	var origin: Vector3 = caster.aim_origin()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + caster.aim_direction() * distance, mask)
	query.exclude = [caster.get_rid()]
	return caster.get_world_3d().direct_space_state.intersect_ray(query)


## "treant" for a tree's trunk, "golem" for a standing stone of the ring, "" for anything else -
## the terrain above all, which shares their layer.
static func _scenery_kind(collider: Node) -> String:
	if collider == null:
		return ""
	if collider.name == "StoneCollision":
		return "golem"
	if collider.name == "Body" and collider.get_parent() != null and collider.get_parent().find_child("Mesh", false, false) != null:
		return "treant"
	return ""
