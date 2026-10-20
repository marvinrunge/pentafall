"""Four-legged gallop for the werewolf (wolf form), built procedurally on the Mixamo rig.

The arms work as forelegs. Temporary controls drive the limbs (IK on ForeArm and Leg,
Damped Track on Hand, Foot and Toe, Damped Track on Neck and Head toward a look point);
the body (Hips position and pitch, spine flex) is set straight on the bones. Every frame
is posed from the gait below, then the visual result is baked into plain bone keys on the
action ww_run4 and the controls are removed. Re-running rebuilds the action from scratch.

Gait: a transverse gallop. World units at the rig's own scale (the builder rescales).
Stance paws are pinned to the floor while the body moves forward at STRIDE per cycle, so
nothing slides; the builder measures that root motion for the playback speed.

Run in Blender with werewolf.blend's scene active:
    exec(open(r"<this file>").read()); build()        # or preview(phase) to pose one frame
"""
import bpy, math, mathutils
from mathutils import Vector, Matrix, Quaternion

ARM = "Armature"
ACTION = "ww_run4"
P = "mixamorig:"

CYCLE = 20                 # frames per gait cycle (30 fps)
STRIDE = 0.90              # metres travelled per cycle
DUTY = {"Hand": 0.33, "Foot": 0.38}   # share of the cycle each paw is on the ground
# touchdown phase per limb (L/R = the character's left/right; left is +X, forward is -Y)
TOUCHDOWN = {"LeftFoot": 0.00, "RightFoot": 0.08, "LeftHand": 0.42, "RightHand": 0.50}
LATERAL = {"LeftFoot": 0.11, "RightFoot": -0.11, "LeftHand": 0.16, "RightHand": -0.16}

HIPS_Z = 0.40
HIPS_BOB = 0.025           # up in the suspension phase
HIPS_PITCH = 84.0          # degrees forward from upright
PITCH_SWING = 5.0          # nose-up after the hind push, nose-down on the fore landing
SPINE_FLEX = 6.0           # degrees per spine bone, arched when gathered
HIND_NEUTRAL = 0.00        # paw mid-stance, forward of the hip joint
FORE_NEUTRAL = 0.02        # paw mid-stance, forward of the shoulder joint
WRIST_Z, ANKLE_Z = 0.09, 0.085
SWING_H = {"Hand": 0.13, "Foot": 0.10}
HEAD_LOOK = Vector((0.0, -0.35, 1.0))   # head's up-axis aims this way (slightly forward)
NECK_LOOK_INFLUENCE = 0.55
# IK pole angles, measured (Mixamo mirrors the bone roll, so left and right differ):
# elbows bend back, knees forward, both a little outward. -90 everywhere had the knees
# bending backward and the elbows folding in - the "legs on backwards" look.
POLE_ANGLE = {"LeftElbow": 15, "RightElbow": 165, "LeftKnee": 115, "RightKnee": 55}
FINGER_STANCE = (28.0, -8.0)   # knuckle, claw joints (degrees, +X lifts)
FINGER_SWING = (5.0, -25.0)


def ss(t):
    t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)


def _arm():
    return bpy.data.objects[ARM]


def _empty(name):
    ob = bpy.data.objects.get(name)
    if not ob:
        ob = bpy.data.objects.new(name, None); ob.empty_display_size = 0.03
        bpy.context.scene.collection.objects.link(ob)
    return ob


CTRL = {}


def setup():
    arm = _arm()
    names = []
    for side in ("Left", "Right"):
        for n in ("wrist", "paw", "pole_elbow", "ankle", "ball", "toe", "pole_knee"):
            names.append("ww_ctrl_%s_%s" % (side, n))
    names += ["ww_ctrl_look"]
    for n in names:
        CTRL[n] = _empty(n)
    for pb in arm.pose.bones:
        for c in [c for c in pb.constraints if c.name.startswith("ww_")]:
            pb.constraints.remove(c)
        pb.rotation_mode = "QUATERNION"
    for side in ("Left", "Right"):
        fa = arm.pose.bones[P + side + "ForeArm"]
        c = fa.constraints.new("IK"); c.name = "ww_ik"; c.target = CTRL["ww_ctrl_%s_wrist" % side]
        c.pole_target = CTRL["ww_ctrl_%s_pole_elbow" % side]; c.pole_angle = math.radians(POLE_ANGLE[side + "Elbow"]); c.chain_count = 2
        h = arm.pose.bones[P + side + "Hand"]
        c = h.constraints.new("DAMPED_TRACK"); c.name = "ww_aim"; c.target = CTRL["ww_ctrl_%s_paw" % side]
        lg = arm.pose.bones[P + side + "Leg"]
        c = lg.constraints.new("IK"); c.name = "ww_ik"; c.target = CTRL["ww_ctrl_%s_ankle" % side]
        c.pole_target = CTRL["ww_ctrl_%s_pole_knee" % side]; c.pole_angle = math.radians(POLE_ANGLE[side + "Knee"]); c.chain_count = 2
        f = arm.pose.bones[P + side + "Foot"]
        c = f.constraints.new("DAMPED_TRACK"); c.name = "ww_aim"; c.target = CTRL["ww_ctrl_%s_ball" % side]
        t = arm.pose.bones[P + side + "ToeBase"]
        c = t.constraints.new("DAMPED_TRACK"); c.name = "ww_aim"; c.target = CTRL["ww_ctrl_%s_toe" % side]
    for n, infl in (("Neck", NECK_LOOK_INFLUENCE), ("Head", 1.0)):
        c = arm.pose.bones[P + n].constraints.new("DAMPED_TRACK"); c.name = "ww_aim"
        c.target = CTRL["ww_ctrl_look"]; c.influence = infl


def _set_world(pb, M):
    arm = _arm()
    pb.matrix = arm.matrix_world.inverted() @ M


def pose(frame):
    """Pose the body and place every control for this frame (frame 0 = phase 0)."""
    arm = _arm(); W = arm.matrix_world
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
    p = (frame / CYCLE) % 1.0
    travel = STRIDE * frame / CYCLE                    # forward = -Y
    # --- body
    flex = SPINE_FLEX * math.cos(2 * math.pi * (p - 0.9))
    pitch = HIPS_PITCH - PITCH_SWING * math.sin(2 * math.pi * p) - flex
    hz = HIPS_Z + HIPS_BOB * math.cos(2 * math.pi * (p - 0.75))
    hips = arm.pose.bones[P + "Hips"]
    rest = W @ arm.data.bones[P + "Hips"].matrix_local
    R = Matrix.Rotation(math.radians(pitch), 4, "X") @ rest.to_3x3().to_4x4()
    R.translation = Vector((0.0, -travel, hz))
    _set_world(hips, R)
    bpy.context.view_layer.update()
    for n in ("Spine", "Spine1", "Spine2"):
        arm.pose.bones[P + n].rotation_quaternion = Quaternion((1, 0, 0), math.radians(flex))
    bpy.context.view_layer.update()
    # --- joints the paws hang from
    hip_j = {s: W @ arm.pose.bones[P + s + "UpLeg"].head for s in ("Left", "Right")}
    sho_j = {s: W @ arm.pose.bones[P + s + "Arm"].head for s in ("Left", "Right")}
    # neutral paw spots in body-relative forward distance (from the root's travel)
    for limb, td in TOUCHDOWN.items():
        side = "Left" if limb.startswith("Left") else "Right"
        fore = limb.endswith("Hand")
        joint_fwd = -(sho_j[side].y if fore else hip_j[side].y) - travel
        neutral = joint_fwd + (FORE_NEUTRAL if fore else HIND_NEUTRAL)
        q = (p - td) % 1.0
        duty = DUTY["Hand" if fore else "Foot"]
        land = STRIDE * (math.floor((frame / CYCLE) - td) + td) + neutral + STRIDE * duty / 2
        if q < duty:
            fwd = land; lift = 0.0; s = 0.0
        else:
            s = (q - duty) / (1 - duty)
            fwd = land + STRIDE * ss(s); lift = SWING_H["Hand" if fore else "Foot"] * math.sin(math.pi * s) ** 0.8
        x = LATERAL[limb]
        if fore:
            wrist = Vector((x, -fwd, WRIST_Z + lift))
            fold = math.sin(math.pi * s) if s > 0 else 0.0
            paw_off = Vector((0, -0.065, -0.07)).lerp(Vector((0, 0.05, -0.075)), fold)
            CTRL["ww_ctrl_%s_wrist" % side].location = wrist
            CTRL["ww_ctrl_%s_paw" % side].location = wrist + paw_off
            CTRL["ww_ctrl_%s_pole_elbow" % side].location = Vector((x * 1.0, sho_j[side].y + 0.35, wrist.z + 0.15))
            # fingers: lifted and splayed forward on the ground (+X lifts), curled up in the air
            base = FINGER_STANCE[0] + (FINGER_SWING[0] - FINGER_STANCE[0]) * fold
            tipc = FINGER_STANCE[1] + (FINGER_SWING[1] - FINGER_STANCE[1]) * fold
            for fin in ("Index", "Middle", "Ring", "Pinky"):
                arm.pose.bones[P + side + "Hand" + fin + "1"].rotation_quaternion = Quaternion((1, 0, 0), math.radians(base))
                for j in ("2", "3"):
                    arm.pose.bones[P + side + "Hand" + fin + j].rotation_quaternion = Quaternion((1, 0, 0), math.radians(tipc))
        else:
            ankle = Vector((x, -fwd + 0.045, ANKLE_Z + lift))
            flick = math.sin(math.pi * s) if s > 0 else 0.0
            ball_off = Vector((0, -0.045, -0.077)).lerp(Vector((0, 0.03, -0.085)), flick)
            ball = ankle + ball_off
            toe_dir = Vector((0, -0.07, 0.0)).lerp(Vector((0, 0.02, -0.06)), flick)
            CTRL["ww_ctrl_%s_ankle" % side].location = ankle
            CTRL["ww_ctrl_%s_ball" % side].location = ball
            CTRL["ww_ctrl_%s_toe" % side].location = ball + toe_dir
            CTRL["ww_ctrl_%s_pole_knee" % side].location = Vector((x * 1.4, hip_j[side].y - 0.4, ankle.z + 0.25))
    # anchored on the neck base (moved by the spine only), not the head: the head's own
    # position still carries the previous frame's aim and made the loop drift
    neck = W @ arm.pose.bones[P + "Neck"].head
    CTRL["ww_ctrl_look"].location = neck + HEAD_LOOK
    bpy.context.view_layer.update()


def preview(phase=0.0):
    arm = _arm(); arm.animation_data.action = None
    setup(); pose(phase * CYCLE)


def teardown():
    arm = _arm()
    for pb in arm.pose.bones:
        for c in [c for c in pb.constraints if c.name.startswith("ww_")]:
            pb.constraints.remove(c)
    for n in list(CTRL) or [o.name for o in bpy.data.objects if o.name.startswith("ww_ctrl_")]:
        ob = bpy.data.objects.get(n)
        if ob: bpy.data.objects.remove(ob, do_unlink=True)
    CTRL.clear()


def build():
    arm = _arm(); scene = bpy.context.scene
    arm.animation_data.action = None
    setup()
    frames = list(range(0, CYCLE + 1))
    baked = []
    for f in frames:
        pose(f)
        local = {}
        for pb in arm.pose.bones:
            m = arm.convert_space(pose_bone=pb, matrix=pb.matrix, from_space="POSE", to_space="LOCAL")
            local[pb.name] = m.copy()
        baked.append(local)
    teardown()
    old = bpy.data.actions.get(ACTION)
    if old: bpy.data.actions.remove(old)
    act = bpy.data.actions.new(ACTION); act.use_fake_user = True
    arm.animation_data.action = act
    for i, f in enumerate(frames):
        for pb in arm.pose.bones:
            if "Tail" in pb.name or "Jaw" in pb.name:
                continue
            loc, rot, _ = baked[i][pb.name].decompose()
            pb.rotation_quaternion = rot
            pb.keyframe_insert("rotation_quaternion", frame=f + 1, group=pb.name)
            if pb.name == P + "Hips":
                pb.location = loc
                pb.keyframe_insert("location", frame=f + 1, group=pb.name)
    try:
        if act.slots: arm.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    scene.frame_start, scene.frame_end = 1, CYCLE + 1
    return act
