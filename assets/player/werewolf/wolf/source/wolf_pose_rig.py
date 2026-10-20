"""Posing rig for hand-keyed werewolf clips: you set the key poses, the bake does the rest.

make_rig(clip, source=None, keys=(...))
    Adds controls (collection WW_Controls) and constraints to the Armature, and keys the
    controls IN PLACE at the given frames - from `source` if given (an existing ww_* action,
    e.g. the procedural gallop), else from the current pose. The armature gets an action
    `<clip>_keys` holding the bones you pose by hand (spine, shoulders, fingers).
bake_rig(clip, cycle_frames=None)
    Evaluates the rig every frame and writes plain bone keys to `<clip>` (what gets exported).
    For a loop (cycle_frames = frames per cycle) it also measures how fast the planted paws
    slide back, turns that into forward root motion so they stay put, and closes the loop.
    The rig is muted afterwards, not deleted: make_rig(clip, resume=True) picks it up again.

Controls (all Empties; forward is -Y, the character's left is +X):
    WW_Body                 the hips: move = body position, rotate = body pitch/roll/yaw
    WW_Paw_Front_L/R        wrist position (IK target)      child WW_Aim_Front_*: where the paw points
    WW_Paw_Hind_L/R         ankle (hock) position (IK)      children WW_Aim_Ball_* / WW_Aim_Toe_*
    WW_Elbow_L/R, WW_Knee_L/R   which way elbows / knees point (children of WW_Body)
    WW_Look                 where the head looks (child of WW_Body)
Spine, Spine1, Spine2, shoulders and fingers: rotate the bones themselves in Pose Mode.
"""
import bpy, math
from mathutils import Vector, Matrix

ARM = "Armature"
P = "mixamorig:"
COLL = "WW_Controls"
POLE_ANGLE = {"LeftElbow": 15, "RightElbow": 165, "LeftKnee": 115, "RightKnee": 55}
NECK_LOOK_INFLUENCE = 0.55
SIDES = (("Left", "L"), ("Right", "R"))
HAND_BONES = ("Spine", "Spine1", "Spine2", "Neck", "LeftShoulder", "RightShoulder")


def _arm():
    return bpy.data.objects[ARM]


def _coll():
    c = bpy.data.collections.get(COLL)
    if not c:
        c = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(c)
    return c


def _empty(name, shape="SPHERE", size=0.03, parent=None):
    ob = bpy.data.objects.get(name)
    if not ob:
        ob = bpy.data.objects.new(name, None)
        _coll().objects.link(ob)
    ob.empty_display_type = shape; ob.empty_display_size = size
    ob.parent = parent; ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.rotation_mode = "XYZ"
    return ob


def _controls():
    body = _empty("WW_Body", "CUBE", 0.07)
    c = {"body": body}
    for side, s in SIDES:
        c["paw_f_" + s] = _empty("WW_Paw_Front_" + s, "SPHERE", 0.035)
        c["aim_f_" + s] = _empty("WW_Aim_Front_" + s, "PLAIN_AXES", 0.02, c["paw_f_" + s])
        c["paw_h_" + s] = _empty("WW_Paw_Hind_" + s, "SPHERE", 0.035)
        c["aim_b_" + s] = _empty("WW_Aim_Ball_" + s, "PLAIN_AXES", 0.02, c["paw_h_" + s])
        c["aim_t_" + s] = _empty("WW_Aim_Toe_" + s, "PLAIN_AXES", 0.02, c["paw_h_" + s])
        c["elbow_" + s] = _empty("WW_Elbow_" + s, "CONE", 0.025, body)
        c["knee_" + s] = _empty("WW_Knee_" + s, "CONE", 0.025, body)
    c["look"] = _empty("WW_Look", "SINGLE_ARROW", 0.15, body)
    return c


def _constrain(c, mute=False, poles=None, neck_look=NECK_LOOK_INFLUENCE):
    arm = _arm()
    angles = dict(POLE_ANGLE); angles.update(poles or {})
    for pb in arm.pose.bones:
        for k in [k for k in pb.constraints if k.name.startswith("ww_")]:
            pb.constraints.remove(k)
    def add(bone, kind, target, **kw):
        k = arm.pose.bones[P + bone].constraints.new(kind); k.name = "ww_rig"; k.target = target
        for a, v in kw.items(): setattr(k, a, v)
        k.mute = mute
        return k
    add("Hips", "COPY_TRANSFORMS", c["body"])
    for side, s in SIDES:
        add(side + "ForeArm", "IK", c["paw_f_" + s], pole_target=c["elbow_" + s],
            pole_angle=math.radians(angles[side + "Elbow"]), chain_count=2)
        add(side + "Hand", "DAMPED_TRACK", c["aim_f_" + s])
        add(side + "Leg", "IK", c["paw_h_" + s], pole_target=c["knee_" + s],
            pole_angle=math.radians(angles[side + "Knee"]), chain_count=2)
        add(side + "Foot", "DAMPED_TRACK", c["aim_b_" + s])
        add(side + "ToeBase", "DAMPED_TRACK", c["aim_t_" + s])
    if neck_look > 0:      # the gallop aims the neck too; clips made since key it instead
        add("Neck", "DAMPED_TRACK", c["look"], influence=neck_look)
    add("Head", "DAMPED_TRACK", c["look"])


def _set_action(ob, act):
    if not ob.animation_data: ob.animation_data_create()
    ob.animation_data.action = act
    try:
        if act and act.slots: ob.animation_data.action_slot = act.slots[0]
    except Exception:
        pass


def _key_world(ob, M, frame):
    prev = ob.rotation_euler.copy()
    ob.matrix_world = M
    # keep the angles continuous with the previous key: matrix_world hands back angles in
    # -180..180, and 176 -> -178 would spin the control almost a full turn in between
    ob.rotation_euler = ob.rotation_euler.to_matrix().to_euler(ob.rotation_mode, prev) \
        if ob.rotation_mode in ("XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX") else ob.rotation_euler
    ob.keyframe_insert("location", frame=frame); ob.keyframe_insert("rotation_euler", frame=frame)


def unwrap_euler_keys():
    """Shift every control's Euler keys by whole turns so neighbouring keys are never more
    than 180 degrees apart on a channel (what Blender's Euler Filter does). Run by the bake;
    safe to run any time."""
    fixed = 0
    for ob in _coll().objects:
        act = ob.animation_data.action if ob.animation_data else None
        if not act:
            continue
        for fc in _all_fcurves(act):
            if fc.data_path != "rotation_euler":
                continue
            kps = sorted(fc.keyframe_points, key=lambda k: k.co[0])
            for a, b in zip(kps, kps[1:]):
                d = b.co[1] - a.co[1]
                turns = round(d / (2 * math.pi))
                if turns:
                    shift = -turns * 2 * math.pi
                    b.co[1] += shift; b.handle_left[1] += shift; b.handle_right[1] += shift
                    fixed += 1
            fc.update()
    return fixed


def make_rig(clip, source=None, keys=(1,), resume=False):
    arm = _arm(); scene = bpy.context.scene; W = arm.matrix_world
    c = _controls()
    if resume:
        for pb in arm.pose.bones:          # clear what the last bake left on un-keyed bones
            pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
        for ob in c.values():              # each clip has its own control animation
            a = bpy.data.actions.get("%s__%s" % (clip, ob.name))
            if a: _set_action(ob, a)
        _constrain(c, poles=dict(arm.get("ww_pole_" + clip, {}) or {}),
                   neck_look=arm.get("ww_neck_" + clip, NECK_LOOK_INFLUENCE))
        _set_action(arm, bpy.data.actions.get(clip + "_keys")); return c
    for ob in c.values():
        # a fresh control action per clip, named <clip>__<control>, so setting up one clip
        # never overwrites another clip's keys
        name = "%s__%s" % (clip, ob.name)
        old = bpy.data.actions.get(name)
        if old: bpy.data.actions.remove(old)
        a = bpy.data.actions.new(name); a.use_fake_user = True
        _set_action(ob, a)
    # sample the source pose at each key frame, then key the controls (in place). Any rig
    # constraints still on the bones would bend the source pose, so they go first.
    for pb in arm.pose.bones:
        for k in [k for k in pb.constraints if k.name.startswith("ww_")]:
            pb.constraints.remove(k)
        pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
    if source:
        _set_action(arm, bpy.data.actions[source])
    samples = {}
    hips0 = None
    for f in keys:
        scene.frame_set(f)
        wp = lambda n: (W @ arm.pose.bones[P + n].head).copy()
        wt = lambda n: (W @ arm.pose.bones[P + n].tail).copy()
        hipsM = (W @ arm.pose.bones[P + "Hips"].matrix).copy()
        if hips0 is None: hips0 = hipsM.translation.copy()
        shift = Vector((0, hipsM.translation.y - hips0.y, 0))       # take the travel out
        s = {"body": hipsM, "shift": shift}
        for side, k in SIDES:
            s["wrist_" + k] = wp(side + "Hand"); s["paw_" + k] = wt(side + "Hand")
            s["elbow_" + k] = wp(side + "ForeArm"); s["shoulder_" + k] = wp(side + "Arm")
            s["ankle_" + k] = wp(side + "Foot"); s["ball_" + k] = wp(side + "ToeBase"); s["toe_" + k] = wp(side + "Toe_End")
            s["knee_" + k] = wp(side + "Leg"); s["hip_" + k] = wp(side + "UpLeg")
        s["neck"] = wp("Neck"); s["head_dir"] = (W.to_3x3() @ arm.pose.bones[P + "Head"].matrix.to_3x3()).col[1]
        s["bones"] = {n: arm.pose.bones[P + n].matrix_basis.copy() for n in HAND_BONES}
        s["fingers"] = {pb.name: pb.matrix_basis.copy() for pb in arm.pose.bones if "Hand" in pb.name and pb.name[-1].isdigit()}
        samples[f] = s
    # a separate armature action for the hand-posed bones
    old = bpy.data.actions.get(clip + "_keys")
    if old: bpy.data.actions.remove(old)
    ka = bpy.data.actions.new(clip + "_keys"); ka.use_fake_user = True
    _set_action(arm, ka)
    arm["ww_neck_" + clip] = 0.0          # neck keyed from the source, only the head aims
    _constrain(c, neck_look=0.0)
    T = lambda v, s: v - s["shift"]
    for f, s in samples.items():
        body = s["body"].copy(); body.translation = T(body.translation, s)
        _key_world(c["body"], body, f)
        bpy.context.view_layer.update()
        BW = c["body"].matrix_world
        for side, k in SIDES:
            _key_world(c["paw_f_" + k], Matrix.Translation(T(s["wrist_" + k], s)), f)
            _key_world(c["paw_h_" + k], Matrix.Translation(T(s["ankle_" + k], s)), f)
            bpy.context.view_layer.update()
            for name, pt, par in (("aim_f_", "paw_", "paw_f_"), ("aim_b_", "ball_", "paw_h_"), ("aim_t_", "toe_", "paw_h_")):
                ob = c[name + k]; ob.location = c[par + k].matrix_world.inverted() @ T(s[pt + k], s)
                ob.keyframe_insert("location", frame=f)
            # poles: 0.3 m out from the joint, in the direction it bends, kept relative to the body
            sh = T(s["shoulder_" + k], s); el = T(s["elbow_" + k], s); wr = T(s["wrist_" + k], s)
            el_dir = (el - (sh + wr) / 2).normalized()
            # knees: along the leg's own bend too (the upright idle stands bow-legged, the
            # gallop knees-forward - a fixed direction suited only one of them)
            kn = T(s["knee_" + k], s); hp = T(s["hip_" + k], s); an = T(s["ankle_" + k], s)
            kn_dir = (kn - (hp + an) / 2)
            kn_dir = kn_dir.normalized() if kn_dir.length > 1e-4 else Vector((0, -1, 0.35)).normalized()
            for name, pos in (("elbow_", el + el_dir * 0.3), ("knee_", kn + kn_dir * 0.3)):
                ob = c[name + k]; ob.location = BW.inverted() @ pos; ob.keyframe_insert("location", frame=f)
        look = c["look"]; look.location = BW.inverted() @ (T(s["neck"], s) + s["head_dir"] * 1.0)
        look.keyframe_insert("location", frame=f)
        for n, m in s["bones"].items():
            pb = arm.pose.bones[P + n]; pb.rotation_mode = "QUATERNION"; pb.matrix_basis = m
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
        for n, m in s["fingers"].items():
            pb = arm.pose.bones[n]; pb.rotation_mode = "QUATERNION"; pb.matrix_basis = m
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
    scene.frame_start, scene.frame_end = min(keys), max(keys)
    for ob in c.values():
        ob.show_in_front = True
    _calibrate_poles(clip, samples[keys[0]], keys[0])
    return c


def _calibrate_poles(clip, s, frame):
    """Pick each IK pole angle so the rig reproduces the source pose's elbows and knees at
    the first key (the angle that works depends on the pose: Mixamo's mirrored bone roll
    plus how the limb is turned). Stored on the armature per clip; _constrain reads it."""
    arm = _arm(); scene = bpy.context.scene; W = arm.matrix_world
    scene.frame_set(frame)
    found = {}
    for side, k in SIDES:
        for bone, joint, key in ((side + "ForeArm", side + "ForeArm", "elbow_"), (side + "Leg", side + "Leg", "knee_")):
            ik = next(c for c in arm.pose.bones[P + bone].constraints if c.type == "IK")
            want = s[key + k] - s["shift"]
            def err(a):
                ik.pole_angle = math.radians(a); bpy.context.view_layer.update()
                return ((W @ arm.pose.bones[P + joint].head) - want).length
            best = min(range(-180, 180, 5), key=err)
            fine = min([best + d * 0.5 for d in range(-10, 11)], key=err)
            ik.pole_angle = math.radians(fine)
            found[side + ("Elbow" if key == "elbow_" else "Knee")] = (round(fine, 1), round(err(fine) * 100, 2))
    arm["ww_pole_" + clip] = {n: v[0] for n, v in found.items()}
    bpy.context.view_layer.update()
    print("pole angles for %s (deg, cm off):" % clip, found)


def _all_fcurves(act):
    try:
        return list(act.fcurves)
    except Exception:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out += list(bag.fcurves)
        return out


def close_loop_keys(clip, first, last):
    """Make the key at `last` an exact copy of the key at `first` on every control and on
    the hand-posed bones, so the inbetweens run smoothly back into the first pose."""
    acts = [ob.animation_data.action for ob in _coll().objects if ob.animation_data and ob.animation_data.action]
    ka = bpy.data.actions.get(clip + "_keys")
    if ka: acts.append(ka)
    for act in acts:
        for fc in _all_fcurves(act):
            v = fc.evaluate(first)
            for kp in [kp for kp in fc.keyframe_points if abs(kp.co[0] - last) < 0.01]:
                fc.keyframe_points.remove(kp)
            fc.keyframe_points.insert(last, v)
            fc.update()


PAW_CONTROLS = ("WW_Paw_Front_L", "WW_Paw_Front_R", "WW_Paw_Hind_L", "WW_Paw_Hind_R")
PLANT_TOLERANCE = 0.02     # a paw within this of its lowest height counts as planted
# hind paws are pinned by the ball of the foot (the ankle lifts as the foot rolls);
# forepaws by the wrist, which stays put on these paws
CONTACT = {"WW_Paw_Hind_L": "WW_Aim_Ball_L", "WW_Paw_Hind_R": "WW_Aim_Ball_R"}
FLOOR_CLEARANCE = 0.004    # toe and finger tips are lifted to at least this
FALLBACK_SPEED = 0.045     # m per frame when the keys don't slide the planted paws back


def _plan_pins(frames, scene):
    """For a cycle posed in place: find each paw's planted frames (cyclic), measure how fast
    planted paws slide back, and return per-frame overrides that make every planted paw
    slide back at exactly that speed from where it touched down. With root motion added at
    the same speed, each planted paw then stands still on the floor."""
    pos = {n: [] for n in PAW_CONTROLS}
    contact = {n: [] for n in PAW_CONTROLS}     # the part that is on the floor
    for f in frames:
        scene.frame_set(f)
        for n in PAW_CONTROLS:
            pos[n].append(bpy.data.objects[n].matrix_world.translation.copy())
            c = CONTACT.get(n)
            contact[n].append(bpy.data.objects[c].matrix_world.translation.copy() if c else pos[n][-1])
    N = len(frames)
    windows = {}
    slides = []
    for n, pts in pos.items():
        # ground height: the median of the four lowest heights (a single dipped key, like a
        # hock dropped on the push-off, must not redefine the floor)
        low = sorted(p.z for p in pts)[:4][1:3]
        ground = sum(low) / len(low)
        down = [p.z <= ground + PLANT_TOLERANCE for p in pts]
        if all(down):
            continue
        start = next(i for i in range(N) if down[i] and not down[i - 1])   # cyclic touchdown
        runs, i = [], start
        for _ in range(N):
            if down[i % N] and not down[(i - 1) % N]:
                runs.append([])
            if down[i % N]:
                runs[-1].append(i % N)
            i += 1
        windows[n] = runs
        for r in runs:
            if len(r) >= 2:
                slides.append((pts[r[-1]].y - pts[r[0]].y) / (len(r) - 1))     # +Y = back
    # one speed for every paw: the median, so a single hurried key doesn't set the pace
    slides.sort()
    speed = slides[len(slides) // 2] if slides else 0.0
    if speed < 0.01:
        speed = FALLBACK_SPEED
    pins = {}
    for n, runs in windows.items():
        ob = bpy.data.objects[n]; pts = pos[n]; con = contact[n]
        planted = {}
        for r in runs:
            td = con[r[0]]
            for k, i in enumerate(r):
                # pin the contact point; the paw keeps its posed offset from it (so a foot
                # rolling onto its toes on the push-off still rolls)
                want = Vector((td.x, td.y + speed * k, td.z))
                planted[i] = pts[i] + (want - con[i])
        # swing frames: the posed path, shifted by however far the pin moved the lift-off
        # point, faded out by the next touchdown so the swing lands where it was posed
        for r in runs:
            end = r[-1]; gap = []
            i = (end + 1) % N
            while i not in planted and len(gap) < N:
                gap.append(i); i = (i + 1) % N
            d = planted[end] - pts[end]
            for k, i in enumerate(gap):
                t = (k + 1) / (len(gap) + 1); fade = 1 - t * t * (3 - 2 * t)
                planted.setdefault(i, pts[i] + d * fade)
        for i, loc in planted.items():
            pins.setdefault(frames[i], []).append((ob, loc))
    report = {n: [[frames[i] for i in r] for r in runs] for n, runs in windows.items()}
    print("planted frames:", report, "| speed %.4f m/frame" % speed)
    return pins, speed


def _lift_toes(arm):
    """Raise a paw's aim target until its tips clear the floor (a few passes, since the
    bone only points at the target): hind toes via WW_Aim_Toe_*, fore claws via WW_Aim_Front_*."""
    W = arm.matrix_world
    for side, s in SIDES:
        checks = (
            ("WW_Aim_Toe_" + s, lambda: (W @ arm.pose.bones[P + side + "Toe_End"].tail).z),
            ("WW_Aim_Front_" + s, lambda: min((W @ arm.pose.bones[P + side + "Hand" + fn + "4"].tail).z
                                              for fn in ("Index", "Middle", "Ring", "Pinky"))),
        )
        for aim_name, tip_z in checks:
            aim = bpy.data.objects[aim_name]
            for _ in range(6):
                tip = tip_z()
                if tip >= FLOOR_CLEARANCE - 1e-4:
                    break
                M = aim.matrix_world.copy(); M.translation.z += (FLOOR_CLEARANCE - tip) * 1.5
                aim.matrix_world = M
                bpy.context.view_layer.update()


def bake_rig(clip, frame_start, frame_end, cycle_frames=None):
    """Bake the rig into `clip`. For a loop, frame_end is the last frame of the cycle
    (frame_end + 1 is written as frame_start moved forward by the measured stride)."""
    arm = _arm(); scene = bpy.context.scene; W = arm.matrix_world
    # Start from the rest pose: bones the keys don't animate (the IK legs) otherwise keep
    # whatever the previous bake left on them, and the IK solver starts from there - a
    # leftover straight leg made it miss its target by 8 cm.
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0); pb.scale = (1, 1, 1)
    for k in [k for pb in arm.pose.bones for k in pb.constraints if k.name.startswith("ww_")]:
        k.mute = False
    _set_action(arm, bpy.data.actions.get(clip + "_keys"))
    unwrap_euler_keys()
    if cycle_frames:
        close_loop_keys(clip, frame_start, frame_start + cycle_frames)
    frames_in = list(range(frame_start, frame_end + 1))
    pins, speed = (_plan_pins(frames_in, scene) if cycle_frames else ({}, 0.0))
    baked = {}
    for f in frames_in:
        scene.frame_set(f)
        for ob, loc in pins.get(f, []):
            ob.location = loc                      # the planted paw, slid back at exactly `speed`
        if pins.get(f):
            bpy.context.view_layer.update()
        _lift_toes(arm)
        baked[f] = {pb.name: arm.convert_space(pose_bone=pb, matrix=pb.matrix, from_space="POSE", to_space="LOCAL").copy()
                    for pb in arm.pose.bones}
    for pb in arm.pose.bones:
        for k in pb.constraints:
            if k.name.startswith("ww_"): k.mute = True
    old = bpy.data.actions.get(clip)
    if old: bpy.data.actions.remove(old)
    act = bpy.data.actions.new(clip); act.use_fake_user = True
    _set_action(arm, act)
    frames = list(range(frame_start, frame_end + 1)) + ([frame_end + 1] if cycle_frames else [])
    for f in frames:
        src = baked[f if f <= frame_end else frame_start]
        for pb in arm.pose.bones:
            if "Tail" in pb.name:          # the tail comes from wolf_secondary.py
                continue
            # the Jaw is baked too: keyed by hand (bite) it is kept; otherwise it sits at rest
            # and wolf_secondary.py replaces it with its own curve
            loc, rot, _ = src[pb.name].decompose()
            pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = rot
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            if pb.name == P + "Hips":
                # root motion: forward (-Y world) by the measured paw slide
                travel = speed * (f - frame_start)
                dl = arm.convert_space(pose_bone=pb, matrix=Matrix.Translation((0, -travel, 0)),
                                       from_space="WORLD", to_space="LOCAL").translation \
                    - arm.convert_space(pose_bone=pb, matrix=Matrix.Identity(4), from_space="WORLD", to_space="LOCAL").translation
                pb.location = loc + dl
                pb.keyframe_insert("location", frame=f, group=pb.name)
    return act, speed * (cycle_frames or 0)
