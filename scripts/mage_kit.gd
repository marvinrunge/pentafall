class_name MageKit
extends AttackKit
## The mage's basic attack: bolts in the colour of the mage's path, and the Arcane Blast
## (docs/CHARACTER_CLASSES_PLAN.md - "a class is the WEAPON, a colour is the MAGIC": the
## colour only paints the bolt, Player.path_color).
##
## The button works the warrior's way round, on the RELEASE: a tap throws a bolt, holding past
## player_heavy_hold_time sets off the blast at once (MeleeKit says why a release-driven button
## can carry both). A bolt is one of the spell pack's three one-handed throws, in turn, played
## on the upper body so the mage walks while throwing; the blast is its two-handed throw,
## rooted, and bursts on whatever it meets.
##
## Nothing leaves the hand on the click. Each throw carries the moment the hand is fastest
## (measured by tools/player_character_builder.gd) and the bolt is loosed then, from the hand,
## at what the crosshair is on - so a throw cut off before its release throws nothing.
##
## The bolt is resolved on this machine, like the axe and the arrow (MageBolt), and flown on
## the other screens as a picture (Player._net_spawn_bolt).
##
## Prowess, the level-3 class skill, lives here too: every colour spell cast gives a charge
## (on_spell_cast) and the next bolt or blast spends it for a harder, bigger shot.

## The throws a bolt takes in turn, one per click. Only the first for now: of the pack's three
## it is the one that throws straight ahead - bolt_2 turns the whole body side-on and bolt_3
## ends with the hand thrown up at the sky. The other two stay in the library until better
## ones are picked.
var bolt_clips: Array[String] = ["bolt_1"]
var blast_clip: String = "arcane_blast"

## Which throw the next bolt uses.
var _next_bolt: int = 0
## Seconds the attack button has been held, or -1 when it is not down.
var _hold_timer: float = -1.0
## A resolved press ("L" or "H") held for player_attack_buffer_time, so a release that lands
## just before the throw in flight can be chained out of still throws.
var _buffered: String = ""
var _buffered_timer: float = 0.0
## When, in seconds of the action in flight (Player._action_elapsed), the shot leaves the
## hand; -1 when nothing is waiting to.
var _release_at: float = -1.0
var _release_blast: bool = false
## The throw in flight is a bolt (not the blast) - for the walking pace.
var _throwing_bolt: bool = false

## Prowess: charges banked by colour spells, each spent by one bolt or blast, all lost
## mage_prowess_window seconds after the last spell.
var prowess_charges: int = 0
var _prowess_timer: float = 0.0
## Motes round the throwing hand while Prowess charges are waiting - denser the more there
## are - in the colour of the path. Built on first use, on the mage's own screen.
var _prowess_glow: GPUParticles3D = null
var _prowess_glow_color: String = "-"


func _init(owner: Player) -> void:
	player = owner


func tick(delta: float) -> void:
	if _hold_timer >= 0.0:
		_hold_timer += delta
	if _buffered_timer > 0.0:
		_buffered_timer -= delta
		if _buffered_timer <= 0.0:
			_buffered = ""
	if _prowess_timer > 0.0:
		_prowess_timer -= delta
		if _prowess_timer <= 0.0:
			prowess_charges = 0
	if player._action_timer <= 0.0:
		_throwing_bolt = false
	_update_prowess_glow()


func land_due_hits() -> void:
	if _release_at >= 0.0 and player._action_elapsed >= _release_at:
		_release_at = -1.0
		_loose(_release_blast)


func read_input() -> void:
	# Press and release checked independently, as MeleeKit does: a click fast enough to land
	# both inside one frame is a zero-length hold, a tap.
	if Input.is_action_just_pressed("attack"):
		_hold_timer = 0.0
	if Input.is_action_just_released("attack") and _hold_timer >= 0.0:
		_buffered = "H" if _hold_timer >= GameSettings.player_heavy_hold_time else "L"
		_buffered_timer = GameSettings.player_attack_buffer_time
		_hold_timer = -1.0
	# Held long enough to be the blast: it goes off now rather than on the release.
	if _hold_timer >= GameSettings.player_heavy_hold_time and player._can_start_attack():
		drop_swing()
		_throw_blast()
	if _buffered != "" and player._can_start_attack():
		var symbol: String = _buffered
		drop_swing()
		if symbol == "H":
			_throw_blast()
		else:
			_throw_bolt()


func drop_swing() -> void:
	_hold_timer = -1.0
	_buffered = ""
	_buffered_timer = 0.0


## The throw was cut off before its release: no bolt.
func drop_hits() -> void:
	_release_at = -1.0


func reset_chain() -> void:
	_next_bolt = 0


func move_speed_mult() -> float:
	return GameSettings.mage_bolt_move_mult if _throwing_bolt and player._action_timer > 0.0 else 1.0


## A colour spell has just been cast by this player (Player.execute_spell, on their own
## machine). Prowess banks a charge for the next shot.
func on_spell_cast(_spell_id: String) -> void:
	if not player.has_class_skill("mage_prowess"):
		return
	prowess_charges = mini(prowess_charges + 1, GameSettings.mage_prowess_max_charges)
	_prowess_timer = GameSettings.mage_prowess_window
	player._spawn_cast_flash(MageBolt.tint_of(player.path_color()), 0.9)


func _update_prowess_glow() -> void:
	if _prowess_glow == null:
		if prowess_charges <= 0:
			return
		_prowess_glow = SpellFx.sparks(Color.WHITE, 0.06, 14, 0.5, "mote")
		_prowess_glow.name = "ProwessGlow"
		_prowess_glow.one_shot = false
		_prowess_glow.explosiveness = 0.0
		_prowess_glow.lifetime = 0.45
		player.add_child(_prowess_glow)
	_prowess_glow.emitting = prowess_charges > 0
	if prowess_charges <= 0:
		return
	_prowess_glow.amount_ratio = float(prowess_charges) / float(maxi(GameSettings.mage_prowess_max_charges, 1))
	var orb: MageHandOrb = player.animator.hand_orb()
	_prowess_glow.global_position = orb.palm_point() if orb != null else player.animator.hand_point(true)
	var color: String = player.path_color()
	if color != _prowess_glow_color:
		_prowess_glow_color = color
		(_prowess_glow.process_material as ParticleProcessMaterial).color_ramp = SpellFx._premul_ramp(MageBolt.tint_of(color))


# --- the throws -------------------------------------------------------------------------------

func _throw_bolt() -> void:
	var clip: String = bolt_clips[_next_bolt % bolt_clips.size()]
	_next_bolt = (_next_bolt + 1) % bolt_clips.size()
	# Fervor quickens the throw the way it quickens a swing.
	var duration: float = GameSettings.mage_bolt_duration / player._attack_speed_mult()
	player._pending_cast_id = ""
	# Upper body and not rooted: the legs keep walking under a throw. Marked as a basic attack
	# (is_melee), which is what lets the next throw chain out of this one and a spell cut it
	# off (Player._yield_melee_to_cast).
	player._begin_action(clip, duration, true, false, true)
	_throwing_bolt = true
	_schedule_release(clip, false)


func _throw_blast() -> void:
	reset_chain()
	var duration: float = GameSettings.mage_blast_duration / player._attack_speed_mult()
	player._pending_cast_id = ""
	player._begin_action(blast_clip, duration, false, true, true)
	# After _begin_action, whose _commit_action clears it (.agents/learnings.md, the barbarian):
	# a blast is a full-body commitment nothing may chain out of.
	player._action_is_heavy = true
	_throwing_bolt = false
	_schedule_release(blast_clip, true)


func _schedule_release(clip: String, blast: bool) -> void:
	var hits: Array[float] = player.animator.hit_times(clip, player._action_duration)
	_release_at = hits[0] if not hits.is_empty() else player._action_duration * 0.5
	_release_blast = blast


## Heard as the shot leaves the hand (_loose), not as the throw starts: the blast's wind-up
## ran ahead of its own sound by over half a second, and a throw cut off before its release
## throws nothing and should not sound like it did.
func _play_throw_sound() -> void:
	player._play_sound(&"spell_cast", player.global_position + Vector3(0.0, 1.3, 0.0))


## The shot itself: from the throwing hand (both hands, for the blast), at what the crosshair
## is on, carrying everything a basic attack carries.
func _loose(blast: bool) -> void:
	_play_throw_sound()
	var damage_mult: float = GameSettings.mage_blast_damage_mult if blast else GameSettings.mage_bolt_damage_mult
	var damage: float = GameSettings.spell_melee_damage * damage_mult
	damage *= player.get_spell_damage_multiplier() * player._giant_damage_mult()
	# The rest of what a basic attack carries, exactly as the axe's apply_hit() and the bow
	# spend it: Loxodon Warhammer's share of the health pool, and whatever the throw is charged
	# with (AttackCharges) - the blast is the mage's heavy attack, a bolt its light one.
	damage += player.max_hp * player.equipment_value("loxodon_warhammer")
	var load: RefCounted = player.attack_charges.take(AttackCharges.Weight.HEAVY if blast else AttackCharges.Weight.LIGHT)
	if load != null:
		damage = damage * load.damage_mult + load.damage_add
	var empowered: bool = prowess_charges > 0
	if empowered:
		prowess_charges -= 1
		damage *= GameSettings.mage_prowess_damage_mult

	var color: String = player.path_color()
	var size: float = (2.2 if blast else 1.0) * (1.45 if empowered else 1.0)
	var radius: float = GameSettings.mage_blast_radius if blast else 0.0
	if load != null:
		size *= load.size_mult
		radius = maxf(radius, load.burst_radius)
	var speed: float = GameSettings.mage_blast_speed if blast else GameSettings.mage_bolt_speed
	var shot_range: float = GameSettings.mage_bolt_range
	# A bolt is the orb held over the palm, thrown (MageHandOrb); the blast leaves from between
	# both hands, and takes the orb with it.
	var orb: MageHandOrb = player.animator.hand_orb()
	var hand: Vector3 = player.animator.hand_midpoint().origin if blast else player.animator.hand_point(true)
	if orb != null and not blast:
		hand = orb.palm_point()
	var target: Vector3 = player.aim_hit_point(shot_range)
	var direction: Vector3 = (target - hand).normalized()
	if direction.length_squared() < 0.5:
		direction = -player.global_basis.z
	# Leaving from the orb itself; without one, a hand's width out in front, so the ball is
	# born in front of the fingers rather than inside them.
	var origin: Vector3 = hand if orb != null and not blast else hand + direction * 0.15
	if orb != null:
		orb.spend()
	var bolt := MageBolt.launch(player, origin, direction * speed, color, size, radius, shot_range)
	bolt.authority_damage = damage
	bolt.load = load
	bolt.knockback = GameSettings.mage_blast_knockback if blast else GameSettings.mage_bolt_knockback
	if Net.is_active() and player.is_local:
		player._net_spawn_bolt.rpc(origin, direction * speed, MageBolt.color_index(color), size, radius, shot_range)
