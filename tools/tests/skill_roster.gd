extends Node
## Regression test: does every skill in the roster actually DO something?
##
## Every spell and aura, each cast for real against real enemies, each
## with one assertion about an observable consequence. Not "does it parse" and not "does
## it run without an error" - a spell that silently does nothing passes both of those,
## which is exactly how the skill tree managed to refuse every purchase for a whole
## release while the suite stayed green.
##
## Run with:  godot --headless --path . res://tools/tests/skill_roster.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing each skill that did nothing.

var _frames: int = 0
var _done: bool = false
var _failures: Array[String] = []
var _player: Node = null
var _scene: Node = null
## Sections that ran all the way to their end.
##
## Without this the suite lies. A script error mid-section aborts that section, leaves
## `_failures` empty, and the run prints PASS having checked nothing - which is exactly
## what happened the first time the multicolour section was added, and exactly the class
## of false green this whole file exists to prevent.
var _completed: Array[String] = []

const SECTIONS: Array[String] = ["white", "blue", "black", "red", "green", "auras", "aura_ranks", "ranks", "multicolour", "sounds", "round_two"]

## Every skill that should be audible, and the event it plays. Hand-written on purpose:
## deriving it from SoundBank would only prove SoundBank agrees with itself, and the
## thing worth catching is a spell whose trigger was never wired at all.
const EXPECTED_SPELL_SOUNDS: Dictionary = {
	"white_1": &"spell_exalted_strike",
	"white_2": &"spell_circle_protection",
	"white_3": &"spell_reprisal_ward",
	"white_4": &"spell_wrath_of_god",
	"white_5": &"spell_rally_fallen",
	"blue_1": &"spell_unsummon",
	"blue_2": &"spell_frostwave",
	"blue_3": &"spell_suction",
	"blue_4": &"spell_frost_globe",
	"blue_5": &"spell_cast",
	"black_1": &"spell_doom_blade",
	"black_2": &"spell_contagion",
	"black_3": &"spell_kill",
	"black_4": &"spell_wall_of_souls",
	"black_5": &"spell_zombify",
	"red_1": &"spell_cast",
	"red_2": &"spell_fire_dash",
	"red_3": &"spell_rain_ember",
	"red_4": &"spell_fire_cone",
	"red_5": &"spell_lightning_bolt",
	"green_1": &"heavy_landing",
	"green_2": &"spell_giant_growth",
	"green_3": &"spell_fog",
	"green_4": &"spell_roar",
	"green_5": &"spell_ironbark",
}


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < 90:
		return
	_done = true
	await _run()
	get_tree().quit()


# --- scaffolding ---------------------------------------------------------------

## A live enemy at a world position. Real EnemyBase instances rather than stubs, because
## half of what these skills do is call methods on them - a stub would only prove the
## test's own doubles work.
func _spawn_enemy(offset: Vector3, color: String = "Red", kind: String = "Melee") -> EnemyBase:
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var enemy: EnemyBase = scene.instantiate()
	enemy.set_meta("enemy_color", color)
	enemy.set_meta("enemy_type", kind)
	_scene.add_child(enemy)
	enemy.global_position = _player.global_position + offset
	return enemy


## Clears the field between checks, so one skill's leftovers cannot make the next one
## look like it worked.
func _clear_enemies() -> void:
	for enemy: Node in _scene.get_tree().get_nodes_in_group("enemies"):
		enemy.free()


## Where a spell's zones, walls and summons live now.
##
## They used to be add_child()ed straight onto the scene root. They go through
## MainController's EffectNetSpawner instead, so that every peer gets one rather than only
## the machine that ran the spell, and a MultiplayerSpawner puts what it makes under its
## own spawn_path. Falls back to the root for a stripped scene that has no Effects node.
func _effects_root() -> Node:
	var effects: Node = _scene.get_node_or_null("Effects")
	return effects if effects != null else _scene


func _nodes_of(type: String) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in _effects_root().get_children():
		if child.get_class() == type or (child.get_script() != null and child.get_script().get_global_name() == type):
			found.append(child)
	return found


func _clear_spawned() -> void:
	for type: String in ["FrostGlobe", "WallOfFrost", "SoulWall", "DoTZone", "TemporaryAlly", "SuctionZone"]:
		for node: Node in _nodes_of(type):
			node.free()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


## Offset from the player to a spot on the ground under the crosshair ray, `distance` metres
## along it: where an enemy has to stand to be in the sights. Straight ahead of the character
## is NOT that spot - the camera looks over the right shoulder.
func _under_crosshair(distance: float) -> Vector3:
	var spot: Vector3 = _player.aim_origin() + _player.aim_direction() * distance
	spot.y = _player.global_position.y
	return spot - _player.global_position


## Casts through the same entry point the game uses on the server, so the test exercises
## the real match statement rather than calling the implementations directly.
## Sets a ghoul off with an enemy standing beside it: [health before, health after].
func _ghoul_burst_drop(ghoul: Node3D) -> Array[float]:
	var bystander: EnemyBase = _spawn_enemy(Vector3.ZERO)
	bystander.global_position = ghoul.global_position + Vector3(1.0, 0.0, 0.0)
	var before: float = bystander.health
	ghoul._explode()
	return [before, bystander.health]


func _cast(spell_id: String) -> void:
	_player._run_spell_effect(spell_id, 1.0)


const ChargedHits_ := preload("res://scripts/charged_hits.gd")


## A boss at full health, for the Deathtouch threshold - only its class and health are read.
func _boss_stub() -> EnemyBase:
	var boss: EnemyBase = _spawn_enemy(Vector3(0.0, 0.0, 40.0))
	var data: EnemyData = boss.enemy_data.duplicate() as EnemyData
	data.enemy_class = "Boss"
	boss.enemy_data = data
	boss.health = data.health
	return boss


# --- the checks ----------------------------------------------------------------

func _run() -> void:
	_scene = get_tree().current_scene
	_player = PlayerRegistry.get_local()
	print("TEST scene=%s player=%s" % [_scene, _player != null])
	if _scene == null or _player == null:
		print("TEST RESULT: FAIL (no player)")
		return

	_check_white()
	_check_blue()
	await _check_black()
	await _check_red()
	_check_green()
	_check_auras()
	_check_aura_ranks()
	_check_ranks()
	_check_multicolour()
	_check_sounds()
	await _check_round_two()

	for section: String in SECTIONS:
		if not _completed.has(section):
			_failures.append("section '%s' did not finish - look for a SCRIPT ERROR above" % section)

	if _failures.is_empty():
		print("TEST RESULT: PASS (%d spells, 11 auras, ranks, multicolour)" % SpellDatabase.SPELLS.size())
	else:
		print("TEST RESULT: FAIL - %d failed: %s" % [_failures.size(), ", ".join(_failures)])


## Called as the LAST line of every section. Reaching it is the proof the section ran.
func _done_with(section: String) -> void:
	_completed.append(section)


func _check_white() -> void:
	print("WHITE")
	_player.attack_charges.clear()
	_cast("white_1")
	_check("white_1 Exalted Strike", _player.attack_charges.uses_left("white_1") > 0, "no charge granted")
	# Armed is half of it: an attack has to spend it, a swing, an arrow or a bolt, of either
	# weight. Without a trigger it was armed and rode on nothing, for every class.
	var light: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.LIGHT)
	var heavy: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.HEAVY)
	_check("white_1 rides a light and a heavy attack",
		light != null and light.damage_mult > 1.0 and light.exile and heavy != null and heavy.damage_mult > 1.0,
		"light=%s heavy=%s" % [light.damage_mult if light else "nothing", heavy.damage_mult if heavy else "nothing"])
	_player.attack_charges.clear()

	_player.protection_shield = 0.0
	# The HUD draws the shield from a signal, not from a poll, so a cast that raises the field
	# without announcing it is a shield the player never sees. Both halves are checked.
	var announced: Array[float] = []
	var shield_probe: Callable = func(amount: float) -> void: announced.append(amount)
	SignalBus.player_shield_changed.connect(shield_probe)
	_cast("white_2")
	_check("white_2 Circle of Protection", _player.protection_shield > 0.0, "no shield")
	_check("white_2 tells the HUD about it", not announced.is_empty() and announced[-1] > 0.0,
		"emissions=%d" % announced.size())
	SignalBus.player_shield_changed.disconnect(shield_probe)
	# It has to EXPIRE. Uncapped and permanent, the correct play was to stand in the base
	# recasting it until the pool was arbitrarily large, and the bar happily drew all of it.
	_check("white_2 shield is temporary", _player._protection_shield_timer > 0.0,
		"%.1fs" % _player._protection_shield_timer)
	# ...and recasting refreshes rather than stacks, so two white players covering the same
	# ally cannot multiply it.
	var single: float = _player.protection_shield
	_cast("white_2")
	_check("white_2 refreshes rather than stacks", is_equal_approx(_player.protection_shield, single),
		"%.0f -> %.0f" % [single, _player.protection_shield])
	_player.protection_shield = 0.0
	_player._protection_shield_timer = 0.0

	_player._reprisal_timer = 0.0
	_cast("white_3")
	_check("white_3 Reprisal Ward", _player._reprisal_timer > 0.0, "ward not up")

	var victim: EnemyBase = _spawn_enemy(Vector3(3.0, 0.0, 0.0))
	var before: float = victim.health
	_cast("white_4")
	_check("white_4 Wrath of God", victim.health < before, "%.0f unchanged" % before)
	_clear_enemies()

	_player.hp = 10.0
	_cast("white_5")
	_check("white_5 Rally the Fallen", _player.hp > 10.0, "no heal")
	_done_with("white")


func _check_blue() -> void:
	print("BLUE")
	# In front of the player, which is where a cone skill has to be tested from.
	var forward: Vector3 = -_player.transform.basis.z
	var shoved: EnemyBase = _spawn_enemy(forward * 5.0)
	_cast("blue_1")
	# The Y component is asserted separately: the shove throws enemies off the ground as
	# well as away, and a purely horizontal push would still satisfy a length check.
	_check("blue_1 Unsummon", shoved.knockback_velocity.length() > 0.1 			and shoved.knockback_velocity.y > 0.0 and shoved.stun_timer > 0.0,
		"knock=%.1f lift=%.1f stun=%.1f" % [
			shoved.knockback_velocity.length(), shoved.knockback_velocity.y, shoved.stun_timer])
	_clear_enemies()
	_clear_enemies()

	var frozen: EnemyBase = _spawn_enemy(Vector3(3.0, 0.0, 0.0))
	_cast("blue_2")
	_check("blue_2 Frost Breath", frozen.freeze_timer > 0.0, "not frozen")
	_clear_enemies()

	# Suction is a lingering zone now, not a single shove: the check is the zone being
	# placed and an enemy inside it being marked for the drag. In front of the camera,
	# because that is where the zone lands.
	var pull_dir: Vector3 = -_player.camera.global_basis.z
	pull_dir.y = 0.0
	var pulled: EnemyBase = _spawn_enemy(pull_dir.normalized() * 6.0)
	pulled._suction_timer = 0.0
	_cast("blue_3")
	# Duration is asserted alongside the pull, because Suction's whole identity is how LONG
	# it drags: "a zone exists and it pulls" was already true when the zone lasted two and a
	# half seconds, so it would not have noticed the vortex curve being wrong.
	var zones: Array[Node] = _nodes_of("SuctionZone")
	var vortex_life: float = zones[0]._life_timer if not zones.is_empty() else 0.0
	_check(
		"blue_3 Suction",
		not zones.is_empty()
			and pulled._suction_timer > 0.0
			and vortex_life >= GameSettings.spell_blue_suction_duration - 0.5,
		"zones=%d pull=%.2f life=%.1f" % [zones.size(), pulled._suction_timer, vortex_life])
	_clear_spawned()
	_clear_enemies()

	_clear_spawned()
	_cast("blue_4")
	_check("blue_4 Wall of Frost", not _nodes_of("WallOfFrost").is_empty(), "no wall placed")
	_clear_spawned()

	var before_displace: Vector3 = _player.global_position
	_cast("blue_5")
	_check("blue_5 Displace", _player.global_position.distance_to(before_displace) > 1.0, "did not blink")
	_clear_spawned()
	_done_with("blue")


func _check_black() -> void:
	print("BLACK")
	var forward: Vector3 = -_player.transform.basis.z
	var in_line: EnemyBase = _spawn_enemy(forward * 6.0)
	var aside: EnemyBase = _spawn_enemy(forward * 6.0 + _player.transform.basis.x * 8.0)
	var line_before: float = in_line.health
	var aside_before: float = aside.health
	_cast("black_1")
	# Both halves matter: a "line" that hits everything is a worse Wrath of God.
	_check("black_1 Doom Blade", in_line.health < line_before and is_equal_approx(aside.health, aside_before),
		"line=%.0f aside=%.0f" % [in_line.health, aside.health])
	_clear_enemies()

	# Contagion aims like Kill - whatever the crosshair is on - and then has to SPREAD,
	# which is the whole spell: one sick enemy is only a damage-over-time.
	var patient_zero: EnemyBase = _spawn_enemy(_under_crosshair(11.0))
	var neighbour: EnemyBase = _spawn_enemy(_under_crosshair(11.0) + _player.transform.basis.x * 2.0)
	var sick_before: float = patient_zero.health
	_cast("black_2")
	_check("black_2 Contagion infects its target", patient_zero.contagion_timer > 0.0,
		"timer=%.1f" % patient_zero.contagion_timer)
	# One second of plague, driven directly: the burn tick and the jump both fall inside it.
	patient_zero._tick_contagion(GameSettings.spell_black_contagion_spread_interval + 0.05)
	_check("black_2 Contagion burns", patient_zero.health < sick_before,
		"%.0f -> %.0f" % [sick_before, patient_zero.health])
	_check("black_2 Contagion spreads", neighbour.contagion_timer > 0.0, "neighbour never caught it")
	_clear_enemies()

	# A spell with nothing to act on is not cast: no cooldown. Through execute_spell, the
	# caster's own path, where the cooldown starts - not _cast, which is the server's half.
	_player.spell_cooldown_timers.erase("black_2")
	_player.execute_spell("black_2")
	_check("black_2 with no one in sight is not cast", _player.spell_miss("black_2") != "" \
		and not _player.spell_cooldown_timers.has("black_2"), "cooldown=%s" % _player.spell_cooldown_timers.get("black_2"))
	var sick: EnemyBase = _spawn_enemy(_under_crosshair(9.0))
	_player.execute_spell("black_2")
	_check("black_2 with one in sight is cast", sick.contagion_timer > 0.0 and _player.spell_cooldown_timers.has("black_2"))
	# A miss the server still meets (the target died during the cast) gives the cooldown back -
	# unless it is a Fork copy's, which is not a cast of its own.
	_player._forked_cast = true
	_player.spell_missed("black_2", "test")
	var kept: bool = _player.spell_cooldown_timers.has("black_2")
	_player._forked_cast = false
	_player.spell_missed("black_2", "test")
	_check("black_2 a miss refunds the cooldown, a Fork copy's does not",
		kept and not _player.spell_cooldown_timers.has("black_2"))
	_clear_enemies()

	# Deathtouch (black_3, was Kill) charges the next attack; the charged hit kills. An ordinary
	# death rather than an exile: the corpse stays on the field and feeds Zombify, so the check
	# is the death animation running, not the node being gone. (The crowd and the limit are
	# _check_round_two's.)
	var doomed: EnemyBase = _spawn_enemy(-_player.transform.basis.z * 3.0)
	# Owned: the server only acts on a charge the attacker's build actually holds.
	_set_rank("black_3", 1)
	_cast("black_3")
	var touch: RefCounted = _player.attack_charges.take(1)
	_player._basic_strike(doomed, 1.0, false, true, touch)
	_check("black_3 Deathtouch", not is_instance_valid(doomed) or doomed.is_queued_for_deletion() or doomed.is_dying, "survived")
	# A boss above the threshold walks away from it.
	_check("black_3 Deathtouch spares a healthy boss", not ChargedHits_.executes(_boss_stub(), _player, PackedStringArray(["black_3"])))
	_clear_enemies()

	_clear_spawned()
	_cast("black_4")
	var walls: Array[Node] = _nodes_of("SoulWall")
	# ORIENTATION, not just existence. The wall lies across the approach the caster is
	# looking down, so its curtain's normal - the quad's local +Z - has to point back along
	# the aim. A quarter turn out and it lies ALONG the lane instead, which is the one
	# placement that catches nothing walking down it, and nothing about the node's presence
	# would have caught that.
	var aligned: bool = false
	if not walls.is_empty():
		var facing: Vector3 = -_player.camera.global_basis.z
		facing.y = 0.0
		var normal: Vector3 = walls[0].global_basis.z
		normal.y = 0.0
		aligned = absf(facing.normalized().dot(normal.normalized())) > 0.9
	_check("black_4 Wall of Souls", not walls.is_empty() and aligned,
		"placed=%s aligned=%s" % [not walls.is_empty(), aligned])
	_clear_spawned()

	# Zombify needs corpses, so the test makes some the way the game does.
	var corpse: EnemyBase = _spawn_enemy(Vector3(2.0, 0.0, 2.0))
	corpse._register_corpse()
	_cast("black_5")
	var raised: Array[Node] = _nodes_of("TemporaryAlly")
	_check("black_5 Zombify", raised.size() >= 1 and raised[0].kind == "undead", "nothing raised")
	# Ghouls only fight hand to hand, so a raised archer or mage has to come back on a melee
	# rig - their own `attack` clips are a bow drawn and a spell cast.
	var archer := TemporaryAlly.new()
	archer.configure("undead", 100.0, 5.0, 10.0, _player)
	archer.visual_color = "Red"
	archer.visual_class = "Ranged"
	_scene.add_child(archer)
	var melee_rig: Node = (EnemyBase.MELEE_VISUAL_SCENES["Red"] as PackedScene).instantiate()
	var on_melee_rig: bool = archer._visual != null and archer._visual.scene_file_path == melee_rig.scene_file_path
	melee_rig.free()
	archer.free()
	_check("black_5 a raised archer rises on a melee rig", on_melee_rig, "kept its ranged model")
	# A ghoul FIGHTS: an enemy put in front of it has to lose health to its swings, over real
	# physics frames, without the ghoul bursting - Zombify alone has no burst at all.
	var had_guild: bool = _player.has_guild("guild_rakdos")
	_player.guild_ranks.erase("guild_rakdos")
	if not raised.is_empty():
		var fighter: TemporaryAlly = raised[0] as TemporaryAlly
		var foe: EnemyBase = _spawn_enemy(Vector3.ZERO)
		foe.global_position = fighter.global_position + Vector3(1.0, 0.0, 0.0)
		var foe_before: float = foe.health
		for frame: int in 150:
			await get_tree().physics_frame
			if not is_instance_valid(foe) or foe.health < foe_before:
				break
		var foe_after: float = foe.health if is_instance_valid(foe) else 0.0
		_check("black_5 ghouls fight", foe_after < foe_before and fighter.attack_serial > 0,
			"%.0f -> %.0f, swings %d" % [foe_before, foe_after, fighter.attack_serial])
		_check("black_5 ghouls do not burst on contact", is_instance_valid(fighter) and not fighter._burst,
			"burst on reaching its target")
		_clear_enemies()
	# The END of a ghoul is where Mayhem Devil, the black+red guild node, comes in
	# (TemporaryAlly._explode): without the node it crumbles and hurts nothing, with it the
	# same end is a burst. Both halves are checked, so neither the gate nor the damage behind
	# it can go missing unnoticed.
	if not raised.is_empty() and is_instance_valid(raised[0]):
		var drop: Array[float] = _ghoul_burst_drop(raised[0] as Node3D)
		_check("black_5 ghoul burst is harmless without Mayhem Devil", drop[1] >= drop[0],
			"%.0f -> %.0f" % [drop[0], drop[1]])
	_clear_spawned()
	_clear_enemies()
	_player.guild_ranks["guild_rakdos"] = 1
	corpse = _spawn_enemy(Vector3(2.0, 0.0, 2.0))
	corpse._register_corpse()
	_cast("black_5")
	raised = _nodes_of("TemporaryAlly")
	if raised.is_empty():
		_check("black_5 ghouls burst with Mayhem Devil", false, "nothing raised")
	else:
		var drop: Array[float] = _ghoul_burst_drop(raised[0] as Node3D)
		_check("black_5 ghouls burst with Mayhem Devil", drop[1] < drop[0],
			"%.0f -> %.0f" % [drop[0], drop[1]])
	if not had_guild:
		_player.guild_ranks.erase("guild_rakdos")
	_clear_spawned()
	_clear_enemies()
	_done_with("black")


func _check_red() -> void:
	print("RED")
	# Fireball goes through the projectile pool, so what it proves is that a projectile
	# left the pool - the explosion itself is the pool's own tested path.
	# Thrown from the left hand, it still has to fly AT the crosshair: a bolt parallel to the
	# view from a hand off to one side lands that far off target, which was the long-standing
	# "Fireball goes a bit left".
	# The crosshair on the mark's chest, as a player would hold it: level, the ray runs at
	# head height and can pass clean over a short enemy.
	var level_pitch: float = _player.camera_pivot.rotation.x
	var drop: float = _player.aim_origin().y - (_player.global_position.y + 1.0)
	_player.camera_pivot.rotation.x = -atan2(drop, 18.0)
	var mark: EnemyBase = _spawn_enemy(_under_crosshair(18.0))
	# Jolt takes a few steps to put a freshly spawned body into the ray queries, so without
	# this the crosshair ray passes straight through the mark it was spawned under. (In a
	# real game an enemy has been walking for seconds before anyone aims at it.)
	for i: int in 10:
		await get_tree().physics_frame
	_player._charge_muzzle = _player.global_position + Vector3(0.0, 1.4, 0.0) - _player.transform.basis.x * 0.4
	var muzzle: Vector3 = _player._charge_muzzle
	_cast("red_1")
	var bolt: Projectile = null
	for p: Projectile in ProjectilePool.pool:
		if p.active and p.proj_type == 4 and p.global_position.distance_to(muzzle) < 0.5:
			bolt = p
	var miss: float = INF
	if bolt != null:
		var closest: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
			muzzle, muzzle + bolt.direction * 60.0, mark.global_position, mark.global_position + Vector3.UP * 1.8)
		miss = closest[0].distance_to(closest[1])
	_check("red_1 Fireball flies at the crosshair", miss < 0.3, "passes %.2f m from the mark" % miss)
	_player.camera_pivot.rotation.x = level_pitch
	for p: Projectile in ProjectilePool.pool:
		if p.active and p.has_method("deactivate"):
			p.deactivate()
	_clear_enemies()

	_player._dash_timer = 0.0
	# The dash lives in SpellEffects now, like every other spell body.
	SpellEffects.cast_red_fire_dash(_player)
	_check("red_2 Fire Dash (launch)", _player._dash_timer > 0.0, "no dash")
	_clear_spawned()
	_cast("red_2")
	var dash_zones: Array[Node] = _nodes_of("DoTZone")
	_check("red_2 Fire Dash (trail)", not dash_zones.is_empty() and dash_zones[0].zone_type == "fire_patch", "no fire patch")
	_player._dash_timer = 0.0
	_clear_spawned()

	_cast("red_3")
	var rain_zones: Array[Node] = _nodes_of("DoTZone")
	_check("red_3 Rain of Ember", not rain_zones.is_empty() and rain_zones[0].zone_type == "fire_rain", "no rain zone")
	_clear_spawned()

	_cast("red_4")
	_check("red_4 Fire Cone", _player._channel_id == "red_4", "channel did not start")
	_player._end_channel()

	_clear_spawned()
	_cast("red_5")
	# The bolt is telegraphed, so what exists immediately is the warning, not the damage.
	var telegraphs: int = 0
	for child: Node in _effects_root().get_children():
		if child.name.begins_with("BoltTelegraph"):
			telegraphs += 1
	_check("red_5 Lightning Bolt", telegraphs > 0, "no telegraph")

	# The bolt's whole reason to exist beside four area skills: it is the one red answer to
	# a single big target. Measured on the multiplier rather than on a delayed strike, which
	# lands a telegraph later than this test runs.
	var elite: EnemyBase = _spawn_enemy(Vector3(3.0, 0.0, 0.0))
	elite.apply_elite_modifier("Juggernaut")
	var trash: EnemyBase = _spawn_enemy(Vector3(5.0, 0.0, 0.0))
	var elite_share: float = _player._bolt_target_multiplier(elite, 2.0)
	var trash_share: float = _player._bolt_target_multiplier(trash, 2.0)
	_check("red_5 hits elites harder than trash", elite_share > trash_share and is_equal_approx(trash_share, 1.0),
		"elite x%.2f vs trash x%.2f" % [elite_share, trash_share])
	_clear_enemies()
	_done_with("red")


func _check_green() -> void:
	print("GREEN")
	var victim: EnemyBase = _spawn_enemy(Vector3(2.0, 0.0, 0.0))
	var before: float = victim.health
	_cast("green_1")
	_check("green_1 Titanic Brawl", victim.health < before, "slam missed")
	_clear_enemies()

	var max_before: float = _player.max_hp
	var scale_before: float = _player.scale.y
	_cast("green_2")
	_check("green_2 Giant Growth", _player.is_giant and _player.max_hp > max_before,
		"giant=%s hp=%.0f->%.0f" % [_player.is_giant, max_before, _player.max_hp])
	# The SIZE half, checked separately from the health half because it broke on its own
	# and this test passed the whole time it was broken. A stale duplicate timer in
	# _physics_process reset _giant_scale_mult to 1.0 on every frame the buff was active,
	# so the player grew for part of one frame and was tweened straight back down.
	_check("green_2 sets a size to grow to", _player._giant_scale_mult > 1.0,
		"mult %.2f" % _player._giant_scale_mult)
	_player._sync_giant_scale()
	_check("green_2 actually grows the player", _player._applied_giant_scale > scale_before,
		"applied %.2f, was %.2f" % [_player._applied_giant_scale, scale_before])
	# The regression itself: the size has to SURVIVE the frames after the cast.
	for _step: int in range(10):
		_player._physics_process(0.016)
	_check("green_2 stays big on the frames after the cast", _player._giant_scale_mult > 1.0,
		"mult fell back to %.2f" % _player._giant_scale_mult)
	_player._end_giant_growth()
	_player._sync_giant_scale()

	_clear_spawned()
	_cast("green_3")
	_check("green_3 Fog", not _nodes_of("DoTZone").is_empty(), "no fog")
	# Suppressed damage is invisible, so the cloud also slows what stands in it - the half a
	# player can actually see. Driven directly rather than by waiting for the zone's own tick,
	# which is half a second away and this test does not run frames.
	var fogged: EnemyBase = _spawn_enemy(Vector3(2.0, 0.0, 0.0))
	fogged.suppress_damage(1.0)
	fogged.apply_slow(1.0, GameSettings.spell_green_fog_slow_mult)
	_check("green_3 Fog slows what stands in it", fogged.movement_speed_mult() < 1.0,
		"x%.2f" % fogged.movement_speed_mult())
	_clear_enemies()
	_clear_spawned()

	var taunted: EnemyBase = _spawn_enemy(Vector3(4.0, 0.0, 0.0))
	_cast("green_4")
	_check("green_4 Roar", taunted.taunt_timer > 0.0 and taunted.current_target == _player,
		"taunt=%.1f" % taunted.taunt_timer)
	_clear_enemies()

	_player._ironbark_timer = 0.0
	_cast("green_5")
	_check("green_5 Ironbark", _player._ironbark_timer > 0.0 and _player.is_control_immune(), "not warded")
	_player._ironbark_timer = 0.0
	_done_with("green")


func _check_auras() -> void:
	print("AURAS")
	for color: String in SpellDatabase.COLORS:
		for entry: Dictionary in SpellDatabase.get_auras(color):
			var aura_id: String = String(entry["id"])
			# Aura choices are rankable now, but a fresh branch still starts with no
			# outer choice owned.
			_player.aura_ranks.clear()
			_player._sync_auras()
			_player.grant_aura_rank(aura_id)
			var took_it: bool = _player.get_aura_rank(aura_id) == 1
			var wants_orb: bool = aura_id in ["aura_orb_of_frost", "aura_orb_of_fire", "aura_healing_orb", "aura_grave_pact", "aura_lightning_orb"]
			var has_orb: bool = _player._aura_orbs.size() > 0
			_check("%s %s" % [color, entry["name"]], took_it and has_orb == wants_orb,
				"took=%s orb=%s wanted=%s" % [took_it, has_orb, wants_orb])

	# Each colour's outer pair is still a real choice: one side can rank up, but the
	# other side stays refused.
	_player.aura_ranks.clear()
	_player.grant_aura_rank("aura_fervor")
	_player.grant_aura_rank("aura_fervor")
	_player.grant_aura_rank("aura_orb_of_fire")
	# The INVERSE of what this asserted until auras were removed. A colour's two auras used
	# to be a fork - taking one refused the other for the rest of the run - and this checked
	# that the refusal held. They are ordinary skills now, so both are buyable and each ranks
	# on its own; a player who spends the points gets both.
	_check("both of a colour's auras can be owned",
		_player.get_aura_rank("aura_fervor") == 2 and _player.get_aura_rank("aura_orb_of_fire") == 1,
		"fervor=%d orb=%d" % [_player.get_aura_rank("aura_fervor"), _player.get_aura_rank("aura_orb_of_fire")])
	_player.aura_ranks.clear()
	_player._sync_auras()
	_done_with("auras")

# --- aura ranks ----------------------------------------------------------------

## Does ranking an AURA up actually change anything?
##
## _check_auras proves a aura can be bought and that the right ones grow an orb.
## It says nothing about what the ranks are worth, which is how five auras shipped whose
## rank 1 granted literally nothing: they were written as
##
##     lerpf(1.0, ceiling, get_aura_rank_mult(id) - 1.0)
##
## and get_aura_rank_mult(1) is 1.0, so the lerp weight at rank 1 was zero. Phyrexian
## Arena rank 1 drained the player's health for a damage and speed bonus of exactly x1.0.
## Every check here is the same shape: rank 1 must already beat no aura at all, and rank 5
## must land on the number the aura is documented as giving.
func _check_aura_ranks() -> void:
	print("AURA RANKS")

	for entry: Array in [
		["aura_fervor", GameSettings.aura_fervor_speed_boost, "swing and cast speed"],
		["aura_glorious_anthem", GameSettings.aura_glorious_anthem_ally_damage_mult, "ally damage"],
		["aura_glorious_anthem", GameSettings.aura_glorious_anthem_ally_damage_taken_mult, "ally damage taken"],
		["aura_kodamas_reach", GameSettings.aura_kodamas_reach_area_mult, "area"],
	]:
		var aura_id: String = entry[0]
		var ceiling: float = entry[1]
		var low: float = GameSettings.aura_bonus_mult(ceiling, 1)
		var high: float = GameSettings.aura_bonus_mult(ceiling, GameSettings.spell_max_rank)
		# Anthem's damage-taken ceiling is BELOW 1.0 - its bonus gets smaller as it improves.
		# Measured as distance from 1.0, both directions read the same way: rank 1 off neutral,
		# rank 5 all the way to the listed number.
		_check("%s rank 1 already pays (%s)" % [aura_id, entry[2]],
			not is_equal_approx(low, 1.0) and absf(low - 1.0) > absf(ceiling - 1.0) * 0.2,
			"x%.3f vs neutral 1.0" % low)
		_check("%s rank 5 beats rank 1 (%s)" % [aura_id, entry[2]], absf(high - 1.0) > absf(low - 1.0) * 1.5,
			"x%.3f -> x%.3f" % [low, high])
		_check("%s rank 5 reaches its listed value (%s)" % [aura_id, entry[2]], is_equal_approx(high, ceiling),
			"x%.3f (listed x%.3f)" % [high, ceiling])

	# --- and the same thing measured through the PLAYER, not the curve ----------
	# The curve being right is worth nothing if a call site still passes it through the old
	# lerp. These read the real accessors at both ranks, with the aura genuinely owned.
	_player.aura_ranks.clear()
	_player._sync_auras()
	_player._casting_rank = 1
	var no_aura_area: float = _player._rank_area()
	var no_aura_damage: float = _player.get_spell_damage_multiplier()

	# Kodama's Reach: every spell's area, through the one funnel they all use.
	_player.grant_aura_rank("aura_kodamas_reach")
	var reach_1: float = _player._rank_area()
	for _i: int in range(GameSettings.spell_max_rank - 1):
		_player.grant_aura_rank("aura_kodamas_reach")
	var reach_5: float = _player._rank_area()
	_check("Kodama's Reach rank 1 widens every spell", reach_1 > no_aura_area * 1.01,
		"x%.3f vs x%.3f" % [reach_1, no_aura_area])
	_check("Kodama's Reach rank 5 beats rank 1", reach_5 > reach_1 * 1.05, "x%.3f -> x%.3f" % [reach_1, reach_5])

	# Glorious Anthem is for EVERYONE ELSE: the white player's own damage must not move, and
	# something standing next to them must take less.
	_player.aura_ranks.clear()
	_player.grant_aura_rank("aura_glorious_anthem")
	_check("Glorious Anthem does not buff the singer", is_equal_approx(_player.get_spell_damage_multiplier(), no_aura_damage),
		"%.3f vs %.3f" % [_player.get_spell_damage_multiplier(), no_aura_damage])
	var listener := Node3D.new()
	_scene.add_child(listener)
	listener.global_position = _player.global_position + Vector3(2.0, 0.0, 0.0)
	_check("Glorious Anthem shelters an ally beside the singer", Player.anthem_damage_taken_mult(listener) < 1.0,
		"x%.3f" % Player.anthem_damage_taken_mult(listener))
	_check("Glorious Anthem strengthens an ally beside the singer", Player.anthem_damage_mult(listener) > 1.0,
		"x%.3f" % Player.anthem_damage_mult(listener))
	listener.global_position = _player.global_position + Vector3(GameSettings.aura_glorious_anthem_radius + 5.0, 0.0, 0.0)
	_check("Glorious Anthem has a reach", is_equal_approx(Player.anthem_damage_taken_mult(listener), 1.0),
		"x%.3f far away" % Player.anthem_damage_taken_mult(listener))
	listener.free()

	# Rhystic Study: casting banks shield, and breaking the shield freezes the breaker.
	_player.aura_ranks.clear()
	_player._sync_auras()
	_player.grant_aura_rank("aura_rhystic_study")
	_cast("blue_5")
	_check("Rhystic Study shields a cast", _player.rhystic_shield > 0.0, "shield %.1f" % _player.rhystic_shield)
	var breaker: EnemyBase = _spawn_enemy(Vector3(2.0, 0.0, 0.0))
	_player._invulnerable_timer = 0.0
	# Earlier sections cast Reprisal Ward, whose block chance turns a hit aside entirely -
	# a hit that never lands never breaks the shield, and the check would fail at random.
	_player._reprisal_timer = 0.0
	_player._ironbark_timer = 0.0
	_player.take_damage(_player.rhystic_shield + 5.0, breaker)
	_check("Rhystic Study's shield freezes what breaks it", breaker.freeze_timer > 0.0,
		"freeze %.2fs" % breaker.freeze_timer)
	_clear_enemies()
	_player.hp = _player.max_hp

	# Phyrexian Arena: a spell on cooldown can be paid for in life, and never with a life.
	_player.aura_ranks.clear()
	_player._sync_auras()
	_player.spell_cooldown_timers["black_1"] = 5.0
	_check("no blood casting without Phyrexian Arena", not _player.can_blood_cast("black_1"))
	_player.grant_aura_rank("aura_phyrexian_arena")
	_player.hp = _player.max_hp
	var cost_1: float = _player.blood_cast_cost("black_1")
	_check("Phyrexian Arena prices a spell on cooldown", cost_1 > 0.0 and _player.can_blood_cast("black_1"),
		"cost %.1f" % cost_1)
	for _i: int in range(GameSettings.spell_max_rank - 1):
		_player.grant_aura_rank("aura_phyrexian_arena")
	var cost_5: float = _player.blood_cast_cost("black_1")
	_check("Phyrexian Arena rank 5 is cheaper than rank 1", cost_5 < cost_1 * 0.9, "%.1f -> %.1f" % [cost_1, cost_5])
	_player.hp = cost_5 * 0.5
	_check("Phyrexian Arena never takes the last of a life", not _player.can_blood_cast("black_1"),
		"hp %.1f, cost %.1f" % [_player.hp, cost_5])
	_player.hp = _player.max_hp
	_player.spell_cooldown_timers.erase("black_1")

	# Grave Pact: a death nearby fills the Soul Orb, and the orb throws the soul at an enemy.
	_player.aura_ranks.clear()
	_player._sync_auras()
	_player.grant_aura_rank("aura_grave_pact")
	var soul_orb: Node = _player._aura_orbs.get("aura_grave_pact", null)
	_check("Grave Pact builds a Soul Orb", is_instance_valid(soul_orb), "no orb")
	if is_instance_valid(soul_orb):
		_player._on_enemy_died_near(_player.global_position + Vector3(3.0, 0.0, 0.0))
		_check("a death nearby gives the orb a soul", soul_orb.soul_count() == 1, "souls %d" % soul_orb.soul_count())
		var haunted: EnemyBase = _spawn_enemy(Vector3(4.0, 0.0, 0.0))
		var haunted_before: float = haunted.health
		soul_orb._release_soul()
		_check("the Soul Orb throws its souls", haunted.health < haunted_before and soul_orb.soul_count() == 0,
			"%.0f -> %.0f, souls %d" % [haunted_before, haunted.health, soul_orb.soul_count()])
		_clear_enemies()

	_player.aura_ranks.clear()
	_player._sync_auras()
	_done_with("aura_ranks")


# --- ranks ---------------------------------------------------------------------

## Sets the player to exactly `rank` in `spell_id`, bypassing the tree. The purchase path
## is covered by skill_purchase.gd; what this file cares about is whether the rank changes
## what the spell DOES.
func _set_rank(spell_id: String, rank: int) -> void:
	_player.spell_ranks[spell_id] = rank
	if not _player.unlocked_spells_in_path.has(spell_id):
		_player.unlocked_spells_in_path.append(spell_id)


## Casts once at rank 1 and once at rank 5 and hands both readings back, so each check
## below is one line about which way the number should move.
func _measure(spell_id: String, probe: Callable) -> Array:
	_set_rank(spell_id, 1)
	var low: float = float(probe.call())
	_set_rank(spell_id, GameSettings.spell_max_rank)
	var high: float = float(probe.call())
	return [low, high]


## Damage a single enemy takes from one cast. The enemy is fresh each time, so nothing
## leaks between the two readings.
func _damage_probe(spell_id: String, offset: Vector3) -> float:
	var victim: EnemyBase = _spawn_enemy(offset)
	var before: float = victim.health
	_cast(spell_id)
	var dealt: float = before - victim.health
	_clear_enemies()
	return dealt


func _check_ranks() -> void:
	print("RANKS")

	# --- the three generic curves actually rise -------------------------------
	_check("curve: damage rises", GameSettings.rank_damage_mult(5) > GameSettings.rank_damage_mult(1) * 1.9,
		"x%.2f" % GameSettings.rank_damage_mult(5))
	_check("curve: area rises", GameSettings.rank_area_mult(5) > GameSettings.rank_area_mult(1) * 1.5,
		"x%.2f" % GameSettings.rank_area_mult(5))
	_check("curve: duration rises", GameSettings.rank_duration_mult(5) > GameSettings.rank_duration_mult(1) * 1.4,
		"x%.2f" % GameSettings.rank_duration_mult(5))

	# --- DAMAGE, on one skill per colour that deals it ------------------------
	var forward: Vector3 = -_player.transform.basis.z
	for entry: Array in [
		["white_4", Vector3(3.0, 0.0, 0.0)],
		["blue_2", Vector3(3.0, 0.0, 0.0)],
		["black_1", forward * 6.0],
		["green_1", Vector3(2.0, 0.0, 0.0)],
	]:
		var readings: Array = _measure(entry[0], func() -> float: return _damage_probe(entry[0], entry[1]))
		_check("%s damage scales" % entry[0], readings[1] > readings[0] * 1.5,
			"%.0f -> %.0f" % [readings[0], readings[1]])

	# Doom Blade's rank buys REACH: an enemy past the rank-1 blade is inside the rank-5 one.
	var reach_probe: Vector3 = forward * (GameSettings.spell_black_doom_blade_length + 6.0)
	var reach: Array = _measure("black_1", func() -> float: return _damage_probe("black_1", reach_probe))
	_check("black_1 reach scales", reach[0] <= 0.0 and reach[1] > 0.0, "%.0f -> %.0f" % [reach[0], reach[1]])

	# --- AREA: an enemy outside the rank-1 radius is inside the rank-5 one ----
	# Roar's radius is 14 at rank 1 and 22.4 at rank 5, so 18 units out is the honest
	# test of whether the radius moved at all.
	var far_enemy: EnemyBase = _spawn_enemy(Vector3(18.0, 0.0, 0.0))
	_set_rank("green_4", 1)
	_cast("green_4")
	var taunted_at_1: bool = far_enemy.taunt_timer > 0.0
	far_enemy.taunt_timer = 0.0
	far_enemy.taunt_source = null
	_set_rank("green_4", GameSettings.spell_max_rank)
	_cast("green_4")
	var taunted_at_5: bool = far_enemy.taunt_timer > 0.0
	_check("green_4 radius scales", not taunted_at_1 and taunted_at_5,
		"rank1=%s rank5=%s" % [taunted_at_1, taunted_at_5])
	_clear_enemies()

	# --- DURATION -------------------------------------------------------------
	var ironbark: Array = _measure("green_5", func() -> float:
		_player._ironbark_timer = 0.0
		_cast("green_5")
		return _player._ironbark_timer)
	_check("green_5 duration scales", ironbark[1] > ironbark[0] * 1.4,
		"%.1fs -> %.1fs" % [ironbark[0], ironbark[1]])

	# --- FRACTIONS: must rise, and must NOT run past their ceiling ------------
	var reduction: Array = _measure("green_5", func() -> float:
		_cast("green_5")
		return _player._ironbark_reduction)
	_check("green_5 reduction walks to its ceiling",
		reduction[1] > reduction[0] and is_equal_approx(reduction[1], GameSettings.spell_green_ironbark_reduction_max),
		"%.2f -> %.2f (cap %.2f)" % [reduction[0], reduction[1], GameSettings.spell_green_ironbark_reduction_max])
	_check("green_5 reduction never reaches immunity", reduction[1] < 1.0, "%.2f" % reduction[1])

	var block: Array = _measure("white_3", func() -> float:
		_cast("white_3")
		return _player._reprisal_block_chance)
	_check("white_3 block chance scales", block[1] > block[0] and block[1] <= 1.0,
		"%.2f -> %.2f" % [block[0], block[1]])

	# --- COUNTS ---------------------------------------------------------------
	var charges: Array = _measure("white_1", func() -> float:
		_player.attack_charges.clear()
		_cast("white_1")
		return float(_player.attack_charges.uses_left("white_1")))
	_check("white_1 charges scale", charges[1] > charges[0], "%.0f -> %.0f" % [charges[0], charges[1]])

	var raised_low: int = _raise_and_count(1)
	var raised_high: int = _raise_and_count(GameSettings.spell_max_rank)
	_check("black_5 raises more bodies", raised_high > raised_low, "%d -> %d" % [raised_low, raised_high])

	# --- Kill is the one skill whose COOLDOWN is the rank curve ---------------
	_set_rank("black_3", 1)
	var cooldown_low: float = _player._get_spell_cooldown("black_3")
	_set_rank("black_3", GameSettings.spell_max_rank)
	var cooldown_high: float = _player._get_spell_cooldown("black_3")
	_check("black_3 cooldown falls with rank", cooldown_high < cooldown_low * 0.8,
		"%.0fs -> %.0fs" % [cooldown_low, cooldown_high])

	# --- and a rank the player does not have must not scale anything ----------
	_player.spell_ranks.erase("white_4")
	var unowned: float = _damage_probe("white_4", Vector3(3.0, 0.0, 0.0))
	_set_rank("white_4", 1)
	var owned: float = _damage_probe("white_4", Vector3(3.0, 0.0, 0.0))
	_check("an unowned spell casts at rank 1", is_equal_approx(unowned, owned),
		"%.0f vs %.0f" % [unowned, owned])
	_done_with("ranks")


## Zombify at a given rank, returning how many undead it raised. Needs corpses, so it
## makes more than the maximum any rank could consume.
func _raise_and_count(rank: int) -> int:
	_clear_spawned()
	for i: int in range(GameSettings.spell_black_zombify_count_max + 2):
		var corpse: EnemyBase = _spawn_enemy(Vector3(2.0 + float(i), 0.0, 2.0))
		corpse._register_corpse()
	_set_rank("black_5", rank)
	_cast("black_5")
	var raised: int = _nodes_of("TemporaryAlly").size()
	_clear_spawned()
	_clear_enemies()
	return raised


# --- multicolour ---------------------------------------------------------------

func _check_multicolour() -> void:
	print("MULTICOLOUR")
	_player.spell_ranks.clear()
	_player.unlocked_spells_in_path.clear()
	_player.reset_quick_slots()

	# A red main who also took one blue spell. This is the build the old single
	# `chosen_color_path` made impossible: picking up blue_2 threw the red bar away.
	for spell_id: String in ["red_1", "red_2", "red_3", "blue_2"]:
		_player.grant_spell_rank(spell_id)

	_check("newly bought spells bind themselves",
		_player.quick_slots.slice(0, 4) == ["red_1", "red_2", "red_3", "blue_2"],
		str(_player.quick_slots))

	var castable: Array[String] = []
	for slot: int in range(5):
		if _player.is_spell_unlocked(slot):
			castable.append(_player._get_spell_id_for_slot(slot))
	_check("two colours are castable at once", castable.has("red_1") and castable.has("blue_2"),
		str(castable))

	# Selecting a colour used to REPLACE the bar. It must now only highlight.
	_player.select_color_path("green")
	_check("choosing a colour leaves the bar alone",
		_player._get_spell_id_for_slot(0) == "red_1", _player._get_spell_id_for_slot(0))

	# Rebinding swaps rather than duplicating.
	_player.assign_quick_slot(0, "blue_2")
	_check("rebinding swaps, never duplicates",
		_player.quick_slots[0] == "blue_2" and _player.quick_slots[3] == "red_1",
		str(_player.quick_slots))

	_check("an unowned spell cannot be bound",
		not _player.assign_quick_slot(4, "black_5") and _player.quick_slots[4] == "",
		str(_player.quick_slots))
	_done_with("multicolour")

# --- sound ---------------------------------------------------------------------

## Does every event SoundBank advertises actually have a recording behind it, and does
## every skill have an event?
##
## SoundBank answers a missing file with push_warning and then silence, so a typo in a
## path costs nothing at startup and everything in play - the spell simply makes no
## noise, which is indistinguishable from a spell that did not fire. Neither the parse
## check nor the smoke test can see it, so it is checked here.
func _check_sounds() -> void:
	print("SOUNDS")

	var silent: Array[String] = []
	for event: StringName in SoundBank.EVENT_FILES:
		var streams: Array = SoundBank._streams.get(event, [])
		if streams.is_empty():
			silent.append(String(event))
	_check("every sound event has a recording", silent.is_empty(),
		"silent: %s" % ", ".join(silent))

	# ...and that the files listed are the files on disk, which is the same question
	# asked from the other end - a path can resolve and still be the wrong one.
	var missing: Array[String] = []
	for event: StringName in SoundBank.EVENT_FILES:
		for relative: String in SoundBank.EVENT_FILES[event]:
			if not ResourceLoader.exists(SoundBank.SFX_ROOT + relative):
				missing.append(relative)
	_check("every listed file exists", missing.is_empty(), "missing: %s" % ", ".join(missing))

	var unvoiced: Array[String] = []
	for spell_id: String in EXPECTED_SPELL_SOUNDS:
		var event: StringName = EXPECTED_SPELL_SOUNDS[spell_id]
		if not SoundBank.EVENT_FILES.has(event):
			unvoiced.append("%s (%s)" % [spell_id, event])
	_check("all 25 original skills map to a real event", unvoiced.is_empty(), ", ".join(unvoiced))

	# The two sustained spells have to be told to loop on the IMPORT, not at runtime.
	# A firestorm that plays its clip once and stops is the failure this catches.
	var not_looping: Array[String] = []
	for event: StringName in [&"spell_rain_ember", &"spell_fire_cone", &"crystal_ambience"]:
		var streams: Array = SoundBank._streams.get(event, [])
		if streams.is_empty():
			not_looping.append("%s (no stream)" % event)
			continue
		var stream: AudioStream = streams[0]
		if stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
			not_looping.append(String(event))
	_check("sustained sounds actually loop", not_looping.is_empty(), ", ".join(not_looping))

	# Every boss has to announce itself, in its own voice - the colours here are the
	# same five BossDatabase ships a model for, so a new boss colour fails this until it
	# is given a sound rather than silently arriving mute.
	var voiceless: Array[String] = []
	for color: String in BossDatabase.VISUAL_SCENES:
		var event: StringName = StringName("boss_spawn_" + color.to_lower())
		if not SoundBank.EVENT_FILES.has(event):
			voiceless.append(color)
	_check("every boss has its own arrival sound", voiceless.is_empty(),
		"silent: %s" % ", ".join(voiceless))

	# The global tier has to actually REACH. Measured against the map rather than against
	# a number in the settings file: the spawners are where bosses arrive, and if the
	# falloff does not cover the distance between the two furthest of them then "global"
	# is a comment rather than a fact. At the default 45 units it was silent.
	var spawners: Array = _scene.enemy_spawners
	var furthest: float = 0.0
	for a: Node3D in spawners:
		for b: Node3D in spawners:
			furthest = maxf(furthest, a.global_position.distance_to(b.global_position))
	_check("global sounds reach across the whole map",
		GameSettings.sfx_global_max_distance >= furthest,
		"map is %.0f units wide, falloff reaches %.0f" % [furthest, GameSettings.sfx_global_max_distance])

	# ...and they need voices of their own, or a wave of impacts recycles the pool out
	# from under a four-second boss arrival before it finishes.
	var missing_global: Array[String] = []
	for event: StringName in SoundBank.GLOBAL_EVENTS:
		if not SoundBank.EVENT_FILES.has(event):
			missing_global.append(String(event))
	_check("every global event has a recording", missing_global.is_empty(), ", ".join(missing_global))
	_check("global sounds have their own voices", GameSettings.sfx_global_voices > 0,
		"%d reserved" % GameSettings.sfx_global_voices)

	print("  (%d events, %d recordings, %d global, map %.0f units)" % [
		SoundBank.EVENT_FILES.size(), _recording_count(), SoundBank.GLOBAL_EVENTS.size(), furthest])
	_done_with("sounds")


func _recording_count() -> int:
	var total: int = 0
	for event: StringName in SoundBank.EVENT_FILES:
		total += (SoundBank.EVENT_FILES[event] as Array).size()
	return total


# --- round two (docs/SKILL_DESIGN.md, "Idea backlog - round two") ---------------

const AttackChargesT := preload("res://scripts/attack_charges.gd")
const RoundTwoSpellsT := preload("res://scripts/round_two_spells.gd")

## Every round-two id, so a spell added to SpellDatabase without a check here fails the suite.
const ROUND_TWO_IDS: Array[String] = [
	"white_6", "white_7", "white_8", "white_9", "white_10", "white_11", "white_12",
	"blue_6", "blue_7", "blue_8", "blue_9", "blue_10", "blue_11", "blue_12",
	"black_6", "black_7", "black_8", "black_9", "black_10", "black_11", "black_12",
	"red_6", "red_7", "red_8", "red_9", "red_10", "red_11",
	"green_6", "green_7", "green_8", "green_9", "green_10", "green_11", "green_12",
]


## Points the server-side aim ray (Player._aim_override, what a client's cast arrives with)
## straight at `enemy`, so a targeted spell's choice does not hang on the camera's tilt.
func _aim_at(enemy: Node3D) -> void:
	var origin: Vector3 = _player.global_position + Vector3(0.0, 1.6, 0.0)
	_player._aim_override = [origin, ((enemy.global_position + Vector3(0.0, 1.0, 0.0)) - origin).normalized()]


func _towers_named(tower_id: String) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in _effects_root().get_children():
		if String(child.name).begins_with("Tower_" + tower_id) and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _allies_of_kind(kind: String) -> Array[Node]:
	var out: Array[Node] = []
	for ally: Node in _nodes_of("TemporaryAlly"):
		if String(ally.get("kind")) == kind:
			out.append(ally)
	return out


func _clear_round_two() -> void:
	_clear_spawned()
	_clear_enemies()
	for child: Node in _effects_root().get_children():
		if String(child.name).begins_with("Tower_") or String(child.name).begins_with("BeastTrophy"):
			child.free()
	_player.attack_charges.clear()


## Arms `spell_id`, takes an attack of `weight` and lands it on `enemy` the way a basic attack
## does (Player._basic_strike) - the real path from charge to consequence.
func _charged_hit(spell_id: String, weight: int, enemy: Node3D, damage: float = 1.0) -> RefCounted:
	var load: RefCounted = _player.attack_charges.take(weight)
	if load != null and enemy != null:
		_player._basic_strike(enemy, damage, load.exile, true, load)
	return load


func _check_round_two() -> void:
	print("ROUND TWO")
	var missing: Array[String] = []
	for color: String in SpellDatabase.COLORS:
		for spell_id: String in SpellDatabase.spells_of(color):
			if SpellDatabase.spell_index(spell_id) > 5 and not ROUND_TWO_IDS.has(spell_id):
				missing.append(spell_id)
	_check("every round-two spell has a check here", missing.is_empty(), ", ".join(missing))
	for spell_id: String in ROUND_TWO_IDS:
		_set_rank(spell_id, 1)
	var forward: Vector3 = -_player.transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side: Vector3 = _player.transform.basis.x

	# --- WHITE ---
	_clear_round_two()
	var carried: EnemyBase = _spawn_enemy(-forward * 4.0)
	_cast("white_6")
	_check("white_6 Glorious Charge stuns what it went through", carried.stun_timer > 0.0, "stun=%.1f" % carried.stun_timer)

	_clear_round_two()
	_cast("white_7")
	var smite: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.LIGHT)
	_check("white_7 Smite waits for a HEAVY attack", smite == null and _player.attack_charges.uses_left("white_7") == 1)
	smite = _player.attack_charges.take(AttackChargesT.Weight.HEAVY)
	_check("white_7 Smite hits harder", smite != null and smite.damage_mult > 1.5, "mult=%s" % (smite.damage_mult if smite else 0.0))

	_clear_round_two()
	var lanced: EnemyBase = _spawn_enemy(forward * 7.0)
	_cast("white_8")
	var lance: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.LIGHT)
	_player.resolve_charged_impact(lance, _player.global_position + forward * 2.0, forward)
	_check("white_8 Sunlance blinds the line past the hit", lanced.blind_timer > 0.0, "blind=%.1f" % lanced.blind_timer)

	_clear_round_two()
	var marked: EnemyBase = _spawn_enemy(forward * 3.0)
	_cast("white_9")
	_charged_hit("white_9", AttackChargesT.Weight.LIGHT, marked)
	_player.protection_shield = 0.0
	marked.take_damage(1.0, _player)
	_check("white_9 Mark of Sanctity shields whoever strikes the mark", marked._sanctity_timer > 0.0 and _player.protection_shield > 0.0,
		"mark=%.1f shield=%.0f" % [marked._sanctity_timer, _player.protection_shield])
	_player.protection_shield = 0.0

	_clear_round_two()
	_cast("white_10")
	_player._invulnerable_timer = 0.0
	_player.hp = 5.0
	_player.take_damage(500.0, null)
	_check("white_10 Worship keeps the last point of health", not _player.is_downed and _player.hp >= 1.0, "hp=%.0f downed=%s" % [_player.hp, _player.is_downed])
	RoundTwoSpellsT._worship_zones.clear()
	_player.hp = _player.max_hp

	_clear_round_two()
	var banished: EnemyBase = _spawn_enemy(_under_crosshair(10.0))
	_cast("white_11")
	_check("white_11 Banishing Light seals the circle away", banished._banish_timer > 0.0 and not banished.is_in_group("enemies"),
		"timer=%.1f" % banished._banish_timer)

	# Towers: the rank sets how many of one kind stand at once (1/2/2/3/3), the oldest going.
	_clear_round_two()
	_set_rank("white_12", 1)
	_cast("white_12")
	_cast("white_12")
	var at_one: int = _towers_named("ivory_tower").size()
	_set_rank("white_12", GameSettings.spell_max_rank)
	for i: int in 4:
		_cast("white_12")
	var at_five: int = _towers_named("ivory_tower").size()
	_check("white_12 Ivory Tower: 1 standing at rank 1, 3 at rank 5", at_one == 1 and at_five == 3, "%d / %d" % [at_one, at_five])
	_set_rank("white_12", 1)

	# --- BLUE ---
	_clear_round_two()
	_cast("blue_6")
	_check("blue_6 Mirror Image raises a copy", _allies_of_kind("mirror").size() == 1, "%d" % _allies_of_kind("mirror").size())

	_clear_round_two()
	var chilled: EnemyBase = _spawn_enemy(forward * 3.0)
	_cast("blue_7")
	var uses: int = _player.attack_charges.uses_left("blue_7")
	_charged_hit("blue_7", AttackChargesT.Weight.LIGHT, chilled)
	var frozen_early: bool = chilled.freeze_timer > 0.0
	_charged_hit("blue_7", AttackChargesT.Weight.LIGHT, chilled)
	_charged_hit("blue_7", AttackChargesT.Weight.LIGHT, chilled)
	_check("blue_7 Crippling Chill: three hits, the third freezes", uses == 3 and not frozen_early and chilled.freeze_timer > 0.0,
		"uses=%d early=%s freeze=%.1f" % [uses, frozen_early, chilled.freeze_timer])

	_clear_round_two()
	var caged: EnemyBase = _spawn_enemy(forward * 3.0)
	_cast("blue_8")
	_charged_hit("blue_8", AttackChargesT.Weight.LIGHT, caged)
	_check("blue_8 Ice Cage encases its target", caged._encase_timer > 0.0 and caged._ice_block != null, "timer=%.1f" % caged._encase_timer)

	_clear_round_two()
	var ebbed: EnemyBase = _spawn_enemy(forward * 3.0)
	ebbed.origin_position = _player.global_position + side * 25.0
	_cast("blue_9")
	_charged_hit("blue_9", AttackChargesT.Weight.HEAVY, ebbed)
	_check("blue_9 Time Ebb sends it back where it came from", ebbed.global_position.distance_to(ebbed.origin_position) < 2.0,
		"%.1f m from home" % ebbed.global_position.distance_to(ebbed.origin_position))

	_clear_round_two()
	var caster: EnemyBase = _spawn_enemy(forward * 6.0, "Blue", "Mage")
	caster.is_miniboss = true
	caster._miniboss_special_windup = 1.0
	_cast("blue_10")
	_check("blue_10 Counterspell breaks a special mid-windup", caster._miniboss_special_windup < 0.0, "windup=%.1f" % caster._miniboss_special_windup)

	_clear_round_two()
	var swine: EnemyBase = _spawn_enemy(_under_crosshair(10.0))
	_cast("blue_11")
	_check("blue_11 Curse of the Swine", swine._swine_timer > 0.0 and swine.round_two_state & EnemyBase.R2_SWINE != 0, "timer=%.1f" % swine._swine_timer)

	_clear_round_two()
	_cast("blue_12")
	_check("blue_12 Glacial Fortress goes up", _towers_named("glacial_fortress").size() == 1)

	# --- BLACK ---
	# Deathtouch: one attack, every enemy it reaches up to the limit - 3 at rank 1, 7 at rank 5.
	for rank: int in [1, GameSettings.spell_max_rank]:
		_clear_round_two()
		_set_rank("black_3", rank)
		var crowd: Array[EnemyBase] = []
		for i: int in 10:
			crowd.append(_spawn_enemy(forward * 3.0 + side * (float(i) - 4.5) * 0.6))
		_cast("black_3")
		var touch: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.LIGHT)
		for enemy: EnemyBase in crowd:
			_player._basic_strike(enemy, 1.0, false, true, touch)
		var dead: int = crowd.filter(func(e: EnemyBase) -> bool: return not is_instance_valid(e) or e.is_dying).size()
		var expected: int = GameSettings.rank_count(GameSettings.spell_black_deathtouch_targets, GameSettings.spell_black_deathtouch_targets_max, rank)
		_check("black_3 Deathtouch executes %d at rank %d" % [expected, rank], dead == expected, "killed %d" % dead)
	_set_rank("black_3", 1)
	_clear_round_two()
	_cast("black_3")
	_player.attack_charges.tick(GameSettings.spell_black_deathtouch_window + 0.1)
	_check("black_3 Deathtouch lapses after its window", _player.attack_charges.uses_left("black_3") == 0)

	_clear_round_two()
	_cast("black_6")
	var unholy: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.LIGHT)
	_check("black_6 Unholy Strength turns life into damage", unholy != null and unholy.damage_add > 0.0, "add=%s" % (unholy.damage_add if unholy else 0.0))

	_clear_round_two()
	var bones: EnemyBase = _spawn_enemy(forward * 3.0)
	bones._register_corpse()
	var splintered: EnemyBase = _spawn_enemy(forward * 3.0 + side * 3.0)
	var splinter_before: float = splintered.health
	_cast("black_7")
	var splinters: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.HEAVY)
	_player.resolve_charged_impact(splinters, bones.global_position, forward)
	_check("black_7 Bone Splinters throws the corpse at the living", splintered.health < splinter_before,
		"%.0f -> %.0f" % [splinter_before, splintered.health])

	_clear_round_two()
	_player._undying_used = false
	_player._invulnerable_timer = 0.0
	_player.hp = 0.0
	_player.die()
	_check("black_8 Undying gets back up", not _player.is_downed and _player.hp > 0.0, "hp=%.0f downed=%s" % [_player.hp, _player.is_downed])
	_player._undying_used = true
	_player._invulnerable_timer = 0.0
	_player.hp = _player.max_hp

	_clear_round_two()
	var elite: EnemyBase = _spawn_enemy(_under_crosshair(8.0))
	elite.elite_modifier = "test"
	elite._register_corpse()
	_cast("black_9")
	_check("black_9 Animate Dead raises the elite", _allies_of_kind("raised").size() == 1)

	_clear_round_two()
	var grave: EnemyBase = _spawn_enemy(_under_crosshair(9.0))
	grave._register_corpse()
	var grave_at: Vector3 = grave.global_position
	_cast("black_10")
	_check("black_10 Gravewalk steps into the corpse", _player.global_position.distance_to(grave_at) < 2.5,
		"%.1f m away" % _player.global_position.distance_to(grave_at))

	_clear_round_two()
	_player.hp = _player.max_hp
	_cast("black_11")
	var owed: int = _player._pact_kills_left
	RoundTwoSpellsT.tick_pact(_player, _player._pact_timer + 0.1)
	_check("black_11 Demonic Pact collects its debt", owed == GameSettings.spell_black_pact_kills and _player.hp < _player.max_hp,
		"owed=%d hp=%.0f" % [owed, _player.hp])
	_player.hp = _player.max_hp

	_clear_round_two()
	_cast("black_12")
	_check("black_12 Bontu's Monument goes up", _towers_named("bontus_monument").size() == 1)

	# --- RED ---
	_clear_round_two()
	var flung: EnemyBase = _spawn_enemy(_under_crosshair(8.0))
	# One physics frame, so the ray the spell aims with can see the body that just arrived.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_cast("red_6")
	_check("red_6 Fling seizes it", not flung._fling.is_empty())

	_clear_round_two()
	_cast("red_7")
	_player.hp = _player.max_hp * 0.25
	var frenzy: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.HEAVY)
	_check("red_7 Blood Frenzy hits harder hurt", frenzy != null and frenzy.damage_mult > 1.2, "mult=%s" % (frenzy.damage_mult if frenzy else 0.0))
	_player.hp = _player.max_hp

	_clear_round_two()
	var kegged: EnemyBase = _spawn_enemy(forward * 3.0)
	_cast("red_8")
	_charged_hit("red_8", AttackChargesT.Weight.LIGHT, kegged)
	_check("red_8 Powder Keg sticks", not kegged._keg.is_empty())

	_clear_round_two()
	var peppered: EnemyBase = _spawn_enemy(forward * 5.0)
	var pepper_before: float = peppered.health
	_cast("red_9")
	_check("red_9 Grapeshot", peppered.health < pepper_before, "%.0f -> %.0f" % [pepper_before, peppered.health])

	_clear_round_two()
	var first: EnemyBase = _spawn_enemy(_under_crosshair(8.0))
	var second: EnemyBase = _spawn_enemy(_under_crosshair(8.0) + side * 4.0)
	# One physics frame, so the ray the spell aims with can see the body that just arrived.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var second_before: float = second.health
	_cast("red_10")
	_aim_at(first)
	_cast("black_1")
	_player._aim_override = []
	_check("red_10 Fork casts the next aimed spell again at another", not _player._fork_armed and second.health < second_before,
		"%.0f -> %.0f" % [second_before, second.health])

	_clear_round_two()
	_cast("red_11")
	_check("red_11 Goblin Sharpshooter goes up", _towers_named("goblin_sharpshooter").size() == 1)

	# --- GREEN ---
	_clear_round_two()
	_cast("green_6")
	var immense: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.LIGHT)
	_check("green_6 Become Immense", immense != null and immense.size_mult > 1.0 and immense.damage_mult > 1.0)

	_clear_round_two()
	var rooted: EnemyBase = _spawn_enemy(forward * 3.0)
	_cast("green_7")
	var vines: RefCounted = _player.attack_charges.take(AttackChargesT.Weight.LIGHT)
	_player.resolve_charged_impact(vines, rooted.global_position, forward)
	_check("green_7 Entangling Vines roots", rooted.root_timer > 0.0, "root=%.1f" % rooted.root_timer)

	_clear_round_two()
	var hooked: EnemyBase = _spawn_enemy(_under_crosshair(14.0))
	# One physics frame, so the ray the spell aims with can see the body that just arrived.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_aim_at(hooked)
	_cast("green_8")
	_player._aim_override = []
	var toward: Vector3 = (_player.global_position - hooked.global_position)
	_check("green_8 Kraul Harpooner drags it in", hooked.knockback_velocity.dot(toward) > 0.0, "knock=%s" % hooked.knockback_velocity)

	var stone := StaticBody3D.new()
	stone.name = "StoneCollision"
	_check("green_9 Awaken knows a standing stone from the ground", RoundTwoSpellsT._scenery_kind(stone) == "golem"
		and RoundTwoSpellsT._scenery_kind(_scene) == "")
	stone.free()

	_clear_round_two()
	var trampled: EnemyBase = _spawn_enemy(-forward * 4.0 + side * 0.8)
	_cast("green_10")
	_check("green_10 Overrun throws it aside", absf(trampled.knockback_velocity.dot(side)) > 1.0, "knock=%s" % trampled.knockback_velocity)

	_clear_round_two()
	_player.beast_trophies.clear()
	_cast("green_11")
	var without: int = _allies_of_kind("beast").size()
	var taken: bool = _player.take_trophy("Green", 2.0)
	_cast("green_11")
	_check("green_11 Call of the Herd needs a trophy and spends it", without == 0 and taken and _allies_of_kind("beast").size() == 1
		and _player.beast_trophies.is_empty(), "without=%d taken=%s" % [without, taken])

	_clear_round_two()
	_cast("green_12")
	_check("green_12 Hornet Nest goes up", _towers_named("hornet_nest").size() == 1)

	# Every round-two spell is heard by its own event (SpellEffects.cast_sound).
	var unvoiced: Array[String] = []
	for spell_id: String in ROUND_TWO_IDS:
		if not SoundBank.EVENT_FILES.has(SpellEffects.cast_sound(spell_id)):
			unvoiced.append("%s (%s)" % [spell_id, SpellEffects.cast_sound(spell_id)])
	_check("every round-two spell maps to a real event", unvoiced.is_empty(), ", ".join(unvoiced))

	_clear_round_two()
	_done_with("round_two")
