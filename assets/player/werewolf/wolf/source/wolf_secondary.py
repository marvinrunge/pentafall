"""Jaw + tail layer for the werewolf (wolf form) clips, run inside Blender on werewolf.blend.

The Mixamo clips know nothing about the Jaw and Tail1-4 bones added to the rig, so this
writes those five channels into each kept clip (the ww_* actions, copies of the untouched
clip_* imports):

- Tail: a damped spring driven by the hips (the tail lags behind whatever the body does:
  accelerations, turns, landings), plus a light ambient sway. Loops are simulated three
  times round so the spring has settled, and the last pass is closed exactly onto its start.
- Jaw: a per-clip curve. 0 is the mouth as modelled (open, teeth bared); + closes
  (about +10 shuts it), - opens wider (about -24 is the widest that still looks right).

Re-running replaces the five channels; nothing else in the clips is touched.
Run: exec(open(r"<this file>").read()) in Blender with werewolf.blend's scene active.
"""
import bpy, math, mathutils

ARM = "Armature"
TAILS = ["mixamorig:Tail1", "mixamorig:Tail2", "mixamorig:Tail3", "mixamorig:Tail4"]
JAW = "mixamorig:Jaw"

# clip -> settings. loop: cycles of ambient sway / breath per loop (must be whole numbers).
#   sway: ambient side sway in degrees at the tail root; lift: base tail lift (+ = up)
#   jaw: ("breath", base, amp, cycles) | ("keys", [(frame, deg), ...]) | ("head", base, gain, min)
#        | None = the jaw was keyed by hand (wolf_pose_rig.py) and is left alone
#   extra jaw bumps: list of (centre frame, deg, sigma frames)
CLIPS = {
    "ww_idle":        dict(loop=True, cycles=2, sway=5, lift=0,  jaw=("breath", 7, 2, 2)),
    "ww_idle_look":   dict(loop=False, cycles=3, sway=5, lift=0, jaw=("breath", 7, 2, 3), bumps=[(78, -19, 12)]),
    "ww_walk":        dict(loop=True, cycles=1, sway=8, lift=8,  jaw=("breath", 5, 3, 2)),
    "ww_run_upright": dict(loop=True, cycles=1, sway=9, lift=16, jaw=("breath", 2, 4, 2)),
    # the gallop pitches the hips ~84 deg forward, which swings the tail up: drop it back down
    "ww_run4":        dict(loop=True, cycles=1, sway=7, lift=-28, jaw=("breath", -4, 4, 2)),
    "ww_bite":        dict(loop=False, cycles=1, sway=3, lift=-20, jaw=None),
    "ww_howl":       dict(loop=False, cycles=3, sway=4, lift=6, jaw=("head", 7, 0.65, -24)),
    "ww_taunt":       dict(loop=False, cycles=3, sway=4, lift=4, jaw=("breath", 6, 2, 3), bumps=[(84, -26, 14)]),
    "ww_jump":        dict(loop=False, cycles=2, sway=3, lift=6, jaw=("breath", 6, 1, 2), bumps=[(49, -16, 9)]),
    "ww_leap_attack": dict(loop=False, cycles=2, sway=3, lift=10,
                           jaw=("keys", [(1, 6), (12, 6), (24, -22), (46, -22), (52, 12), (58, 10), (75, 6), (108, 6)])),
    "ww_punch":       dict(loop=False, cycles=1, sway=3, lift=6,
                           jaw=("keys", [(1, 6), (6, -12), (12, -12), (20, 6), (34, 6)])),
    "ww_spin_swipe":  dict(loop=False, cycles=1, sway=3, lift=8,
                           jaw=("keys", [(1, 6), (30, 6), (37, -16), (44, -16), (55, 6), (74, 6)])),
    "ww_death":       dict(loop=False, cycles=2, sway=3, lift=0,
                           jaw=("keys", [(1, 6), (18, 6), (25, -14), (45, -6), (82, -18), (107, -18)])),
}

FPS = 30.0
SPRING_HZ = 2.0        # tail natural frequency
DAMPING = 0.30         # damping ratio
GAIN_ACC = 0.9         # degrees of tail per m/s^2 of hips acceleration (side / vertical)
GAIN_TURN = 0.12       # degrees of tail per deg/s of hips yaw
CLAMP = 32.0           # max spring deflection at the root, degrees
CHAIN_AMP = [0.45, 0.75, 1.0, 1.2]    # share of the deflection per tail bone
CHAIN_DELAY = [0, 2, 4, 6]            # frames of lag per tail bone (whip)


def _set_action(arm, act):
    arm.animation_data.action = act
    try:
        if act.slots:
            arm.animation_data.action_slot = act.slots[0]
    except Exception:
        pass


def _fcurves(act):
    try:
        return list(act.fcurves)
    except Exception:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out += list(bag.fcurves)
        return out


def _remove_channels(act, bone_names):
    try:
        coll = act.fcurves
        for fc in [fc for fc in coll if any('"%s"' % b in fc.data_path for b in bone_names)]:
            coll.remove(fc)
        return
    except Exception:
        pass
    for layer in act.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in [fc for fc in bag.fcurves if any('"%s"' % b in fc.data_path for b in bone_names)]:
                    bag.fcurves.remove(fc)


def _sample_hips(arm, scene, f0, f1):
    """Hips world matrix per frame."""
    hips = arm.pose.bones["mixamorig:Hips"]
    out = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        out.append((arm.matrix_world @ hips.matrix).copy())
    return out


def _drive(mats, loop):
    """Per frame: (side input, lift input) in degrees-equivalent, from the hips motion."""
    n = len(mats)
    tail_off = mathutils.Vector((0.0, 0.12, -0.07))  # tail root relative to hips, world-ish
    pos = [m @ (m.inverted().to_3x3() @ tail_off) for m in mats]
    dt = 1.0 / FPS

    def at(i):
        if loop:
            return i % (n - 1)   # last frame == first frame in a loop
        return max(0, min(n - 1, i))
    side, lift = [], []
    for i in range(n):
        a = (pos[at(i + 1)] - 2 * pos[at(i)] + pos[at(i - 1)]) / (dt * dt)
        m = mats[at(i)].to_3x3().normalized()
        lat = m.col[0].normalized()            # hips local X in world
        up = mathutils.Vector((0, 0, 1))
        q0 = mats[at(i - 1)].to_quaternion(); q1 = mats[at(i + 1)].to_quaternion()
        dq = q0.rotation_difference(q1)
        yaw_rate = math.degrees(dq.angle) * (1 if dq.axis.z >= 0 else -1) * abs(dq.axis.z) / (2 * dt)
        side.append(-a.dot(lat) * GAIN_ACC + yaw_rate * GAIN_TURN)
        lift.append(-a.dot(up) * GAIN_ACC * 0.6)
    return side, lift


def _spring(inputs, loop, passes):
    w = 2 * math.pi * SPRING_HZ; z = DAMPING; dt = 1.0 / FPS
    x = v = 0.0
    n = len(inputs)
    for p in range(passes):
        out = []
        for i in range(n):
            if loop and p > 0 and i == 0:
                out.append(x); continue
            acc = w * w * (inputs[i] - x) - 2 * z * w * v
            v += acc * dt; x += v * dt
            x = max(-CLAMP, min(CLAMP, x))
            out.append(x)
    if loop:  # close the seam exactly: spread the residual over the loop
        r = out[-1] - out[0]
        out = [o - r * i / (n - 1) for i, o in enumerate(out)]
    return out


def _jaw_curve(cfg, n, f0, head_angles):
    kind = cfg["jaw"][0]
    vals = []
    for i in range(n):
        f = f0 + i
        if kind == "breath":
            _, base, amp, cyc = cfg["jaw"]
            vals.append(base + amp * math.sin(2 * math.pi * cyc * i / (n - 1)))
        elif kind == "head":
            _, base, gain, lo = cfg["jaw"]
            rest = min(head_angles)
            vals.append(max(lo, min(base + 2, base - gain * (head_angles[i] - rest))))
        else:
            keys = cfg["jaw"][1]
            if f <= keys[0][0]: vals.append(keys[0][1]); continue
            if f >= keys[-1][0]: vals.append(keys[-1][1]); continue
            for (fa, va), (fb, vb) in zip(keys, keys[1:]):
                if fa <= f <= fb:
                    t = (f - fa) / (fb - fa); t = t * t * (3 - 2 * t)
                    vals.append(va + (vb - va) * t); break
    for c, d, s in cfg.get("bumps", []):
        for i in range(n):
            vals[i] += d * math.exp(-0.5 * ((f0 + i - c) / s) ** 2)
    return vals


def run():
    scene = bpy.context.scene
    arm = bpy.data.objects[ARM]
    for pb in arm.pose.bones:
        if pb.name in TAILS or pb.name == JAW:
            pb.rotation_mode = "QUATERNION"
    report = []
    for name, cfg in CLIPS.items():
        act = bpy.data.actions.get(name)
        if act is None:
            continue                       # not made yet
        own_jaw = cfg["jaw"] is None
        _remove_channels(act, TAILS + ([] if own_jaw else [JAW]))
        _set_action(arm, act)
        for b in TAILS + ([] if own_jaw else [JAW]):
            arm.pose.bones[b].rotation_quaternion = (1, 0, 0, 0)
        f0, f1 = (int(x) for x in act.frame_range)
        n = f1 - f0 + 1
        mats = _sample_hips(arm, scene, f0, f1)
        head = []
        for f in range(f0, f1 + 1):
            scene.frame_set(f)
            head.append(math.degrees(arm.pose.bones["mixamorig:Head"].rotation_quaternion.angle))
        side_in, lift_in = _drive(mats, cfg["loop"])
        passes = 3 if cfg["loop"] else 1
        side = _spring(side_in, cfg["loop"], passes)
        lift = _spring(lift_in, cfg["loop"], passes)
        jaw = None if own_jaw else _jaw_curve(cfg, n, f0, head)
        for i in range(n):
            f = f0 + i
            ph = 2 * math.pi * cfg["cycles"] * i / (n - 1)
            for k, b in enumerate(TAILS):
                j = i - CHAIN_DELAY[k]
                if cfg["loop"]:
                    j %= (n - 1)
                j = max(0, j)
                s = side[j] * CHAIN_AMP[k] + cfg["sway"] * CHAIN_AMP[k] * math.sin(ph - 0.7 * k)
                l = cfg["lift"] * (1.0 if k == 0 else 0.25) + lift[j] * CHAIN_AMP[k] * 0.5
                q = mathutils.Quaternion((0, 0, 1), math.radians(s)) @ mathutils.Quaternion((1, 0, 0), math.radians(l))
                pb = arm.pose.bones[b]; pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
            if jaw is not None:
                pj = arm.pose.bones[JAW]
                pj.rotation_quaternion = mathutils.Quaternion((1, 0, 0), math.radians(jaw[i]))
                pj.keyframe_insert("rotation_quaternion", frame=f, group=JAW)
        report.append("%-15s %3d fr  tail side %5.1f..%5.1f  jaw %s" % (
            name, n, min(side), max(side), "keyed by hand" if jaw is None else "%5.1f..%5.1f" % (min(jaw), max(jaw))))
    print("\n".join(report))


run()
