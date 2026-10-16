"""Procedural clips for the quadruped beast rigs built by beast_rig.py.

Everything is authored in ARMATURE space (forward = -Y, up = +Z) and converted to each
bone's local rest frame before keying, so the clips don't depend on bone rolls.
Clips: idle, walk, run (loops) and attack, special, hit, death (one-shots).
"""
import bpy
import math
from mathutils import Vector, Quaternion, Euler

TAU = 2 * math.pi
LEGS = [('front', 'L'), ('front', 'R'), ('hind', 'L'), ('hind', 'R')]


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def seg(t, a, b):
    """0 before a, eased 0..1 between a and b, 1 after b."""
    return ease((t - a) / max(b - a, 1e-6))


def rot_w(pitch=0.0, roll=0.0, yaw=0.0):
    """Armature-space rotation. pitch about X (positive = nose up, since forward is -Y),
    roll about Y, yaw about Z. Degrees."""
    return Euler((math.radians(-pitch), math.radians(roll), math.radians(yaw)), 'XYZ').to_quaternion()


def tail_rot(up=0.0, yaw=0.0):
    """Tail bones point backward (+Y): a nose-up rotation would drop them, so 'up' lifts the tip."""
    return rot_w(pitch=-up, yaw=yaw)


class Keyer:
    def __init__(self, arm):
        self.arm = arm
        self.M = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}
        self.Mi = {n: m.inverted() for n, m in self.M.items()}
        for pb in arm.pose.bones:
            pb.rotation_mode = 'QUATERNION'

    def reset(self):
        for pb in self.arm.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)

    def set(self, name, loc=None, rot=None):
        pb = self.arm.pose.bones[name]
        if loc is not None:
            pb.location = self.Mi[name] @ Vector(loc)
        if rot is not None:
            M = self.M[name]
            q = (self.Mi[name].to_4x4() @ rot.to_matrix().to_4x4() @ M.to_4x4()).to_quaternion()
            pb.rotation_quaternion = q

    def key_all(self, frame):
        for pb in self.arm.pose.bones:
            pb.keyframe_insert('location', frame=frame)
            pb.keyframe_insert('rotation_quaternion', frame=frame)


def new_action(arm, name):
    old = bpy.data.actions.get(arm.name + '|' + name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(arm.name + '|' + name)
    act.use_fake_user = True
    if not arm.animation_data:
        arm.animation_data_create()
    arm.animation_data.action = act
    return act


def bake(arm, name, frames, pose_fn, loop):
    """pose_fn(K, t) poses the rig for normalised time t (0..1). Loops key t=0..1 inclusive."""
    K = Keyer(arm)
    act = new_action(arm, name)
    for f in range(frames + 1):
        t = f / frames
        if loop and f == frames:
            t = 0.0
        K.reset()
        pose_fn(K, t)
        K.key_all(f + 1)
    act.frame_range = (1, frames + 1)
    act.use_frame_range = True
    act.use_cyclic = loop
    # linear interpolation keeps sampled curves exact
    try:
        fcs = act.fcurves
    except AttributeError:
        fcs = [fc for l in act.layers for s in l.strips for cb in s.channelbags for fc in cb.fcurves]
    for fc in fcs:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
    return act


# ---------------------------------------------------------------- helpers

def tail_names(arm):
    return sorted([b.name for b in arm.data.bones if b.name.startswith('tail')], key=lambda n: int(n[4:]))


def step_foot(phase, stance, stride, lift):
    """Foot offset (dy, dz, pitch_deg) for a foot at cycle phase 0..1.
    Stance: slides back from -stride/2 to +stride/2 (forward is -Y). Swing: arcs forward."""
    p = phase % 1.0
    if p < stance:
        u = p / stance
        return (-stride / 2 + stride * u, 0.0, 0.0, True)
    u = (p - stance) / (1 - stance)
    s = 0.5 - 0.5 * math.cos(math.pi * u)  # eased forward travel
    dy = stride / 2 - stride * s
    dz = lift * math.sin(math.pi * u)
    return (dy, dz, u, False)


# ---------------------------------------------------------------- clips

def make_clips(arm, P, mesh=None):
    """P: per-beast parameters (heights, strides, amplitudes). mesh: the skinned beast; the
    death clip uses its rest vertices to lay chin and tail ON the ground rather than in it."""
    H = P['H']
    # bites (attack, leap): how far past the rest pose the jaw gapes and snaps shut, degrees.
    # Meshy beasts come modelled with the mouth partly open, so shut is past rest.
    bite_open = P.get('bite_open', P['jaw_open'] * 1.25)
    bite_close = P.get('bite_close', 0.0)
    tails = tail_names(arm)
    nt = len(tails)

    def tail_wave(K, t, amp_yaw, amp_pitch, freq=1.0, lag=0.12, base_pitch=0.0):
        for i, n in enumerate(tails):
            w = (i + 1) / nt
            yaw = amp_yaw * w * math.sin(TAU * (freq * t - i * lag))
            pitch = base_pitch + amp_pitch * w * math.sin(TAU * (freq * t - i * lag) + 1.3)
            K.set(n, rot=tail_rot(pitch, yaw))

    # ---------------- idle: breathing, looking around, tail sway
    def idle(K, t):
        br = math.sin(TAU * t)
        K.set('hips', loc=(0, 0, 0.004 * H * br))
        K.set('spine1', rot=rot_w(pitch=0.8 * br))
        K.set('chest', rot=rot_w(pitch=1.2 * br))
        K.set('neck', rot=rot_w(pitch=2.0 * math.sin(TAU * t + 0.5), yaw=6 * math.sin(TAU * t)))
        K.set('head', rot=rot_w(pitch=-1.5 * math.sin(TAU * t + 0.5), yaw=8 * math.sin(TAU * t - 0.4), roll=3 * math.sin(TAU * t)))
        K.set('jaw', rot=rot_w(pitch=P.get('idle_jaw', 3) * (0.5 + 0.5 * math.sin(TAU * 2 * t))))
        tail_wave(K, t, 10, 4, freq=1.0, lag=0.08)

    # ---------------- walk: lateral-sequence four-beat
    def walk(K, t):
        S, lift = P['walk_stride'], P['walk_lift']
        phases = {('hind', 'L'): 0.0, ('front', 'L'): 0.25, ('hind', 'R'): 0.5, ('front', 'R'): 0.75}
        for leg, ph in phases.items():
            dy, dz, u, st = step_foot(t + ph, 0.62, S, lift)
            K.set('IK_%s.%s' % leg, loc=(0, dy, dz))
            if not st:
                K.set('%s_foot.%s' % leg, rot=rot_w(pitch=-P['toe_flex'] * math.sin(math.pi * u)))
        bob = math.cos(TAU * 2 * t)
        K.set('hips', loc=(0, 0, P['walk_bob'] * H * bob), rot=rot_w(roll=2.0 * math.sin(TAU * t), yaw=2.0 * math.sin(TAU * t)))
        K.set('spine1', rot=rot_w(yaw=-1.5 * math.sin(TAU * t)))
        K.set('chest', rot=rot_w(roll=-2.0 * math.sin(TAU * t + 1.57), yaw=-2.0 * math.sin(TAU * t)))
        K.set('neck', rot=rot_w(pitch=2.5 * math.cos(TAU * 2 * t + 0.6), yaw=2.0 * math.sin(TAU * t)))
        K.set('head', rot=rot_w(pitch=-2.0 * math.cos(TAU * 2 * t + 0.6)))
        tail_wave(K, t, 9, 3, freq=1.0, lag=0.1)

    # ---------------- run: bounding gallop with spinal flex
    def run(K, t):
        S, lift = P['run_stride'], P['run_lift']
        phases = {('hind', 'L'): 0.0, ('hind', 'R'): 0.08, ('front', 'L'): 0.5, ('front', 'R'): 0.58}
        for leg, ph in phases.items():
            dy, dz, u, st = step_foot(t + ph, 0.4, S, lift)
            K.set('IK_%s.%s' % leg, loc=(0, dy, dz))
            if not st:
                K.set('%s_foot.%s' % leg, rot=rot_w(pitch=-P['toe_flex'] * 1.3 * math.sin(math.pi * u)))
        flex = math.sin(TAU * t)  # +: gathered (back arched), -: extended
        K.set('hips', loc=(0, 0, P['run_bob'] * H * math.cos(TAU * 2 * t)), rot=rot_w(pitch=-P['run_flex'] * 0.5 * flex))
        K.set('spine', rot=rot_w(pitch=P['run_flex'] * 0.4 * flex))
        K.set('spine1', rot=rot_w(pitch=P['run_flex'] * 0.4 * flex))
        K.set('chest', rot=rot_w(pitch=P['run_flex'] * 0.2 * flex))
        K.set('neck', rot=rot_w(pitch=-6 - 4 * flex))
        K.set('head', rot=rot_w(pitch=3 + 3 * math.cos(TAU * t)))
        K.set('jaw', rot=rot_w(pitch=-P['jaw_open'] * 0.25))
        tail_wave(K, t, 5, 8, freq=1.0, lag=0.1, base_pitch=P.get('run_tail_pitch', 6))

    # ---------------- attack: crouch, lunge, bite, recover (impact around t=0.5)
    def attack(K, t):
        """Bite: rear the head up and to one side, then snap down across (impact ~t=0.5)."""
        sd = P.get('bite_side', 1.0)
        wind = seg(t, 0.0, 0.36) * (1 - seg(t, 0.36, 0.46))
        lunge = seg(t, 0.36, 0.48) * (1 - seg(t, 0.62, 1.0))
        jaw_open = seg(t, 0.08, 0.38) * (1 - seg(t, 0.47, 0.52))
        K.set('hips', loc=(0, 0.09 * H * wind - P['lunge'] * H * lunge, -0.05 * H * wind + 0.01 * H * lunge),
              rot=rot_w(pitch=7 * wind - 5 * lunge, roll=-3 * sd * wind + 3 * sd * lunge))
        K.set('spine1', rot=rot_w(pitch=-4 * wind + 3 * lunge, yaw=4 * sd * wind))
        K.set('chest', rot=rot_w(pitch=-5 * wind - 4 * lunge, yaw=7 * sd * wind - 4 * sd * lunge))
        K.set('neck', rot=rot_w(pitch=30 * wind - 24 * lunge, yaw=22 * sd * wind - 8 * sd * lunge))
        K.set('head', rot=rot_w(pitch=22 * wind - 14 * lunge, yaw=12 * sd * wind - 10 * sd * lunge,
                                roll=-14 * sd * wind + 18 * sd * lunge))
        # gape wide, then snap fully shut on impact and hold the bite before relaxing
        clench = seg(t, 0.46, 0.51) * (1 - seg(t, 0.66, 0.86))
        K.set('jaw', rot=rot_w(pitch=-bite_open * jaw_open + bite_close * clench))
        # lead paw rises on the windup and slams on the lunge
        K.set('IK_front.L', loc=(0, -0.05 * H * lunge + 0.04 * H * wind, 0.12 * H * wind))
        K.set('front_foot.L', rot=rot_w(pitch=-P['toe_flex'] * wind))
        K.set('IK_front.R', loc=(0, -0.03 * H * lunge, 0))
        for i, n in enumerate(tails):
            w = (i + 1) / nt
            K.set(n, rot=tail_rot(12 * w * wind - 6 * w * lunge, -8 * sd * w * wind + 6 * w * math.sin(TAU * t - i * 0.1)))

    # ---------------- special (leap): crouch, pounce forward, bite + shake, hop back to the start
    def leap(K, t):
        D = P.get('leap_dist', 0.5) * H
        J = P.get('leap_height', 0.22) * H
        crouch = seg(t, 0.0, 0.22) * (1 - seg(t, 0.22, 0.28))
        fu = max(0.0, min(1.0, (t - 0.22) / 0.22))           # flight 0.22 .. 0.44
        bu = max(0.0, min(1.0, (t - 0.64) / 0.2))            # hop back 0.64 .. 0.84
        fly = math.sin(math.pi * fu) if 0.0 < fu < 1.0 else 0.0
        hop = math.sin(math.pi * bu) if 0.0 < bu < 1.0 else 0.0
        land = seg(t, 0.42, 0.47) * (1 - seg(t, 0.5, 0.68)) + 0.6 * seg(t, 0.82, 0.86) * (1 - seg(t, 0.86, 1.0))
        travel = D * ease(fu) - D * ease(bu)
        K.set('root', loc=(0, -travel, J * fly + 0.3 * J * hop))
        body_pitch = (14 * fly - 6 * fu * (1 - seg(t, 0.44, 0.6))) * (1 if fu < 1 else 0) - 8 * land - 3 * crouch
        K.set('hips', loc=(0, 0.07 * H * crouch, -0.13 * H * crouch - 0.08 * H * land),
              rot=rot_w(pitch=body_pitch))
        K.set('spine1', rot=rot_w(pitch=-5 * crouch + 4 * fly))
        K.set('chest', rot=rot_w(pitch=-4 * crouch + 3 * fly - 4 * land))
        shake = seg(t, 0.5, 0.53) * (1 - seg(t, 0.6, 0.66))
        sh = math.sin(TAU * 3 * (t - 0.5) / 0.15) * shake
        K.set('neck', rot=rot_w(pitch=-10 * crouch - 8 * fly - 14 * land, yaw=14 * sh))
        K.set('head', rot=rot_w(pitch=10 * crouch + 6 * fly - 6 * land, roll=16 * sh))
        jaw_open = seg(t, 0.24, 0.4) * (1 - seg(t, 0.46, 0.5))
        clench = seg(t, 0.45, 0.5) * (1 - seg(t, 0.64, 0.76))  # jaws locked through the shake
        K.set('jaw', rot=rot_w(pitch=-bite_open * jaw_open + bite_close * clench))
        # in the air the front legs reach for the prey and the hind legs trail
        for side in ('L', 'R'):
            K.set('IK_front.' + side, loc=(0, -0.3 * H * fly, 0.14 * H * fly + 0.05 * H * hop))
            K.set('front_foot.' + side, rot=rot_w(pitch=P['toe_flex'] * 0.6 * fly))
            K.set('IK_hind.' + side, loc=(0, 0.2 * H * fly, 0.06 * H * fly + 0.05 * H * hop))
            K.set('hind_foot.' + side, rot=rot_w(pitch=-P['toe_flex'] * fly))
        for i, n in enumerate(tails):
            w = (i + 1) / nt
            K.set(n, rot=tail_rot(10 * w * crouch + 16 * w * fly - 8 * w * land, 5 * w * math.sin(TAU * t - i * 0.1)))

    # ---------------- special (spin): a full turn on the spot. The tail tip sweeps the whole
    # front half-circle (body yaw 90..270 deg, the fastest part, impact at 180 ~ t=0.5) and the
    # turn carries on to 360 so the beast ends in its rest pose facing the target again.
    feet_rest = {leg: arm.data.bones['IK_%s.%s' % leg].head_local.copy() for leg in LEGS}
    pivot = Vector((0.0, sum(v.y for v in feet_rest.values()) / 4.0, 0.0))  # between the feet

    def spin_angle(t):
        sd = P.get('spin_side', 1.0)
        u = max(0.0, min(1.0, (t - 0.18) / 0.62))
        return sd * (-15.0 * seg(t, 0.0, 0.18) + 375.0 * (u * u * (3 - 2 * u)))

    def turn(deg, p):
        """p turned by deg about the vertical axis through the pivot."""
        q = Euler((0, 0, math.radians(deg)), 'XYZ').to_quaternion()
        return pivot + q @ (Vector(p) - pivot)

    # feet re-plant in diagonal pairs every 90 deg of turn, offset 45 deg between the pairs
    pairs = {('front', 'L'): 0.0, ('hind', 'R'): 0.0, ('front', 'R'): 45.0, ('hind', 'L'): 45.0}

    def foot_angle(a, off, t):
        """Turn angle (0..360, spin direction positive) a foot is planted at or travelling
        between, and its lift 0..1. Pairs step every 90 deg, offset by `off`."""
        if a <= 0.0:
            return 0.0, 0.0                       # windup counter-turn: feet stay put
        if off > 0 and t > 0.8:
            # the offset pair's last plant is at 315: it steps home once the turn is done
            u = seg(t, 0.8, 0.92)
            return 315.0 + 45.0 * u, math.sin(math.pi * u)
        if a <= off:
            u = a / off                           # offset pair takes its first step at once
            return off * ease(u), math.sin(math.pi * u)
        base = off + 90.0 * math.floor((a - off) / 90.0)
        r = (a - base) / 90.0
        if r < 0.5 or base >= 315.0:
            return base, 0.0
        u = (r - 0.5) / 0.5
        nxt = min(base + 90.0, 360.0)
        return base + (nxt - base) * ease(u), math.sin(math.pi * u)

    # per-bone lift that lines the tail chain up at spin_tail_elev degrees above horizontal
    elev = []
    for n in tails:
        b = arm.data.bones[n]
        d = b.tail_local - b.head_local
        elev.append(math.degrees(math.atan2(d.z, d.y)))  # tail bones point backward (+Y)
    target = P.get('spin_tail_elev', 6.0)
    straighten = [target - elev[0]] + [elev[i - 1] - elev[i] for i in range(1, len(elev))]

    def simulate_tail_follow():
        """Secondary motion for the spin: each tail bone is a damped spring chasing its parent's
        yaw. The tip is the softest, so it lags while the turn speeds up and overshoots when the
        body brakes, then settles. Returns per-bone local yaw offsets sampled over t = 0..1."""
        frames = P.get('special_frames', 54)
        T = frames / P.get('fps', 30.0)
        n = len(tails)
        f_base, f_tip = P.get('tail_freq_base', 3.2), P.get('tail_freq_tip', 1.8)
        zeta = P.get('tail_damping', 0.32)
        k = []; c = []
        for i in range(n):
            f = f_base + (f_tip - f_base) * i / max(n - 1, 1)
            wn = TAU * f
            k.append(wn * wn); c.append(2 * zeta * wn)
        steps = 20 * frames
        dt = T / steps
        phi = [0.0] * n; vel = [0.0] * n
        prev_th = spin_angle(0.0)
        out = []
        for s_ in range(steps + 1):
            t = s_ / steps
            th = spin_angle(t)
            th_v = (th - prev_th) / dt if s_ else 0.0
            prev_th = th
            if s_ == 0:
                phi = [th] * n
            parent, parent_v = th, th_v
            for i in range(n):
                acc = k[i] * (parent - phi[i]) + c[i] * (parent_v - vel[i])
                vel[i] += acc * dt
                phi[i] += vel[i] * dt
                parent, parent_v = phi[i], vel[i]
            offs = []
            parent = th
            for i in range(n):
                offs.append(max(-40.0, min(40.0, phi[i] - parent)))
                parent = phi[i]
            out.append(offs)
        return out

    tail_follow = simulate_tail_follow() if P.get('special') == 'spin' else None

    def follow_at(t):
        m = len(tail_follow) - 1
        x = max(0.0, min(1.0, t)) * m
        a = int(x); b = min(a + 1, m); f = x - a
        return [tail_follow[a][i] * (1 - f) + tail_follow[b][i] * f for i in range(len(tails))]

    def tail_spin(K, t):
        sd = P.get('spin_side', 1.0)
        th = spin_angle(t)
        dt = 1.0 / P.get('special_frames', 54)
        omega = (spin_angle(min(t + dt, 1.0)) - spin_angle(max(t - dt, 0.0))) / (2 * dt)  # deg per clip
        w_norm = max(-1.0, min(1.0, omega / 900.0))        # ~1 at the fastest part of the sweep
        crouch = seg(t, 0.0, 0.18) * (1 - seg(t, 0.8, 1.0))
        # whole rig turns about the pivot (root carries body and the IK feet)
        K.set('root', loc=tuple(turn(th, (0, 0, 0))), rot=rot_w(yaw=th))
        # feet: planted in world space between steps, expressed relative to the turned root
        lift = P.get('spin_step_lift', 0.07) * H
        for leg, off in pairs.items():
            fa, up = foot_angle(th * sd, off, t)
            fa *= sd
            rest = feet_rest[leg]
            local = turn(fa - th, rest) - rest
            K.set('IK_%s.%s' % leg, loc=(local.x, local.y, lift * up))
        # body: low and leaning into the turn
        K.set('hips', loc=(0, 0, -0.06 * H * crouch), rot=rot_w(roll=-7 * sd * abs(w_norm)))
        K.set('spine1', rot=rot_w(yaw=-6 * w_norm))
        K.set('chest', rot=rot_w(pitch=-3 * crouch, yaw=-6 * w_norm))
        # head trails the turn a little and keeps an eye out, snarling through the sweep
        K.set('neck', rot=rot_w(pitch=-5 * crouch, yaw=-12 * w_norm))
        K.set('head', rot=rot_w(yaw=-8 * w_norm, roll=6 * w_norm))
        K.set('jaw', rot=rot_w(pitch=-P['jaw_open'] * 0.7 * seg(t, 0.15, 0.35) * (1 - seg(t, 0.65, 0.85))))
        # tail: held out nearly straight for reach (each bone pitched onto a common slightly
        # raised line); its yaw comes from the spring chain - tip lags into the swing, overshoots
        # when the body brakes and swings back. Faded to exactly rest over the last frames.
        stretch = seg(t, 0.12, 0.32) * (1 - seg(t, 0.72, 0.92))
        offs = follow_at(t)
        home = 1 - seg(t, 0.94, 1.0)
        for i, n in enumerate(tails):
            K.set(n, rot=tail_rot(straighten[i] * stretch, offs[i] * home))

    # ---------------- hit: flinch back and recover
    def hit(K, t):
        k = seg(t, 0.0, 0.18) * (1 - seg(t, 0.3, 1.0))
        K.set('hips', loc=(0, 0.06 * H * k, 0.01 * H * k), rot=rot_w(pitch=4 * k, roll=-4 * k))
        K.set('chest', rot=rot_w(pitch=5 * k, yaw=-6 * k))
        K.set('neck', rot=rot_w(pitch=10 * k, yaw=-8 * k))
        K.set('head', rot=rot_w(pitch=8 * k, roll=-10 * k))
        K.set('jaw', rot=rot_w(pitch=-P['jaw_open'] * 0.6 * k))
        for i, n in enumerate(tails):
            K.set(n, rot=tail_rot(8 * k * (i + 1) / nt, -10 * k * (i + 1) / nt))

    # ---------------- death: the legs give way and the beast slams down flat on its belly,
    # legs splayed out to the sides, chin on the ground, tail laid flat (holds last frame)
    bones = arm.data.bones
    belly = P['death_belly'] * H  # rest height of the belly underside: the body sinks this far
    jaw_dead = 0.35  # fraction of jaw_open the dead beast's mouth hangs open

    # feet slide out until each leg lies nearly straight, front legs forward, hind legs back
    splay = {}
    for (end, side) in LEGS:
        sx = 1 if side == 'L' else -1
        up = bones['%s_upper.%s' % (end, side)]
        lo = bones['%s_lower.%s' % (end, side)]
        ik = bones['IK_%s.%s' % (end, side)].head_local
        joint = up.head_local - Vector((0, 0, belly))
        reach = (up.length + lo.length) * P.get('death_leg_reach', 0.9)
        h = max(joint.z - ik.z, 0.0)
        r = math.sqrt(max(reach * reach - h * h, 0.0))
        a = math.radians(P.get('death_front_splay', 40) if end == 'front' else P.get('death_hind_splay', 55))
        out = Vector((sx * math.sin(a), -math.cos(a) if end == 'front' else math.cos(a), 0.0))
        splay[(end, side)] = Vector((joint.x, joint.y, ik.z)) + out * r - ik

    # rest vertices per bone they mostly follow (mesh local == armature space); without a
    # mesh the bone lines stand in for the surface
    by_bone = {}
    if mesh is not None:
        gi = {g.index: g.name for g in mesh.vertex_groups}
        for v in mesh.data.vertices:
            if v.groups and v.index % 2 == 0:
                by_bone.setdefault(gi[max(v.groups, key=lambda g: g.weight).group], []).append(v.co.copy())

    def pts(n):
        return by_bone.get(n) or [bones[n].head_local.copy(), bones[n].tail_local.copy()]

    def pitched(p, deg, about):
        return about + rot_w(pitch=deg) @ (p - about)

    # neck pitch that sets the (slightly open) jaw on the ground once the body is down
    jaw_open_dead = -P['jaw_open'] * jaw_dead
    jh = bones['jaw'].head_local
    head_pts = pts('head') + [pitched(p, jaw_open_dead, jh) for p in pts('jaw')]
    pivot = bones['neck'].head_local

    def head_low(a):
        return min(pitched(p, a, pivot).z for p in head_pts) - belly
    # lowest the head can go without sinking in (or the highest it must rise)
    ok = [a for a in range(-75, 31) if head_low(a) >= 0.02 * H]  # room for the head's roll
    neck_down = min(ok) if ok else max(range(-75, 31), key=head_low)

    # tail: each bone pitched, root to tip, as low as its flesh can lie without sinking in,
    # so the chain runs down to the ground and then flat along it. Keyed as local deltas,
    # since a child inherits its parent's turn.
    tail_flat = []
    chain = []  # (delta, about) of the bones already placed, root first

    def placed(p):
        for up, about in reversed(chain):
            p = pitched(p, -up, about)  # tail_rot(up) is a pitch of -up
        return p.z - belly
    prev = 0.0
    for n in tails:
        b = bones[n]
        dvec = b.tail_local - b.head_local
        elev = math.degrees(math.atan2(dvec.z, dvec.y))  # tail bones point backward (+Y)
        ps = pts(n)
        best = None
        for want in range(-60, 21, 2):
            delta = (want - elev) - prev
            low = min(placed(pitched(p, -delta, b.head_local)) for p in ps)
            if low >= 0.0:
                best = (want, delta)
                break
        if best is None:
            best = (20, (20 - elev) - prev)
        tail_flat.append(best[1])
        chain.append((best[1], b.head_local.copy()))
        prev = best[0] - elev

    def death(K, t):
        throe = seg(t, 0.0, 0.12) * (1 - seg(t, 0.12, 0.3))   # a last rear-up of the head
        hind = seg(t, 0.1, 0.38)                               # hind legs go first ...
        front = seg(t, 0.18, 0.44)                             # ... then the front
        sink = 0.5 * (hind + front)
        bounce = math.sin(math.pi * (t - 0.44) / 0.14) if 0.44 < t < 0.58 else 0.0
        head = seg(t, 0.3, 0.58)
        head_bounce = math.sin(math.pi * (t - 0.58) / 0.12) if 0.58 < t < 0.7 else 0.0
        tail = sink  # a hanging tail would dig into the ground if the body went down first
        settle = seg(t, 0.55, 0.9)
        K.set('hips', loc=(0, 0.02 * H * throe, -belly * sink + 0.025 * H * bounce),
              rot=rot_w(pitch=6 * (hind - front) + 3 * throe, roll=2.5 * settle))
        K.set('spine1', rot=rot_w(pitch=-2 * sink, yaw=3 * settle))
        K.set('chest', rot=rot_w(pitch=-3 * throe, yaw=-2 * settle))
        for (end, side) in LEGS:
            f = front if end == 'front' else hind
            lift = P.get('death_leg_lift', {}).get('%s.%s' % (end, side), 0.0)
            K.set('IK_%s.%s' % (end, side), loc=tuple(splay[(end, side)] * f + Vector((0, 0, lift * f + 0.03 * H * math.sin(math.pi * f)))))
        K.set('neck', rot=rot_w(pitch=12 * throe + neck_down * head + 3 * head_bounce, yaw=5 * settle))
        K.set('head', rot=rot_w(pitch=6 * throe, roll=P.get('death_head_roll', 8) * settle, yaw=6 * settle))
        K.set('jaw', rot=rot_w(pitch=-P['jaw_open'] * (0.7 * seg(t, 0.0, 0.2) * (1 - head) + jaw_dead * head)))
        for i, n in enumerate(tails):
            w = (i + 1) / nt
            K.set(n, rot=tail_rot(tail_flat[i] * tail + 8 * w * throe, 10 * w * settle))

    fps = P.get('fps', 30)
    out = {}
    out['idle'] = bake(arm, 'idle', P.get('idle_frames', 60), idle, True)
    out['walk'] = bake(arm, 'walk', P['walk_frames'], walk, True)
    out['run'] = bake(arm, 'run', P['run_frames'], run, True)
    out['attack'] = bake(arm, 'attack', P.get('attack_frames', 36), attack, False)
    out['hit'] = bake(arm, 'hit', P.get('hit_frames', 16), hit, False)
    out['death'] = bake(arm, 'death', P.get('death_frames', 50), death, False)
    if P.get('special') == 'leap':
        out['special'] = bake(arm, 'special', P.get('special_frames', 48), leap, False)
    elif P.get('special') == 'spin':
        out['special'] = bake(arm, 'special', P.get('special_frames', 54), tail_spin, False)
    return out


def ground_pass(mesh_obj, arm, action, clamp_from=None):
    """Shift the root vertically per frame so the mesh never dips below z=0. From normalised
    time clamp_from on, also pull it down onto the ground (a corpse lies ON the floor)."""
    sc = bpy.context.scene
    arm.animation_data.action = action
    f0, f1 = int(action.frame_range[0]), int(action.frame_range[1])
    Mi = arm.data.bones['root'].matrix_local.to_3x3().inverted()
    pb = arm.pose.bones['root']
    fixes = {}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        e = mesh_obj.evaluated_get(dg)
        m = e.to_mesh()
        z = min(v.co.z for v in m.vertices)
        e.to_mesh_clear()
        t = (f - f0) / max(f1 - f0, 1)
        if z < 0 or (clamp_from is not None and t >= clamp_from):
            fixes[f] = -z
    for f, dz in fixes.items():
        sc.frame_set(f)
        pb.location = pb.location + Mi @ Vector((0, 0, dz))
        pb.keyframe_insert('location', frame=f)
    return {f: round(v, 3) for f, v in fixes.items()}


def fit_death_legs(mesh_obj, arm, P):
    """Measure how far each leg sinks into the ground on the baked death clip's last frame and
    add the lift its IK target needs to P['death_leg_lift'] (rebake afterwards)."""
    sc = bpy.context.scene
    act = bpy.data.actions[arm.name + '|death']
    arm.animation_data.action = act
    sc.frame_set(int(act.frame_range[1]))
    dg = bpy.context.evaluated_depsgraph_get()
    e = mesh_obj.evaluated_get(dg)
    m = e.to_mesh()
    gi = {g.index: g.name for g in mesh_obj.vertex_groups}
    low = {}
    for v in mesh_obj.data.vertices:
        if not v.groups:
            continue
        name = gi[max(v.groups, key=lambda g: g.weight).group]
        for end, side in LEGS:
            if name.startswith(end + '_') and name.endswith('.' + side):
                key = '%s.%s' % (end, side)
                low[key] = min(low.get(key, 1e9), m.vertices[v.index].co.z)
    e.to_mesh_clear()
    lift = dict(P.get('death_leg_lift', {}))
    for key, z in low.items():
        lift[key] = lift.get(key, 0.0) + max(0.0, -z)
    P['death_leg_lift'] = lift
    return {k: round(v, 3) for k, v in lift.items()}


CLIPS = ['idle', 'walk', 'run', 'attack', 'special', 'hit', 'death']


def export_glb(mesh_obj, arm, path):
    """One NLA track per clip (track name = glTF animation name), IK baked by sampling,
    only deform bones exported (IK/pole controllers stay in Blender)."""
    arm.data.bones['root'].use_deform = True  # carries the death roll; no verts weighted to it
    ad = arm.animation_data
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    for clip in CLIPS:
        act = bpy.data.actions.get(arm.name + '|' + clip)
        if act is None:
            continue
        tr = ad.nla_tracks.new()
        tr.name = clip
        st = tr.strips.new(clip, int(act.frame_range[0]), act)
        tr.mute = False
    ad.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    bpy.ops.object.select_all(action='DESELECT')
    mesh_obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_animations=True, export_animation_mode='NLA_TRACKS',
        export_def_bones=True, export_force_sampling=True, export_frame_step=1,
        export_anim_slide_to_zero=True, export_yup=True, export_apply=False,
        export_skins=True, export_all_influences=False)
