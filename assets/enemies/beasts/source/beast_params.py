"""Per-beast settings for beast_anim.make_clips and the jaw split, plus the export targets.

death_belly: lowest point of the body (hips/spine/chest-weighted verts) over H - how far
the death clip drops the body to lay it flat on its belly.
bite_open / bite_close: degrees past the (partly open) rest pose the jaw gapes / snaps shut
in the bites; picked by eye so the mouth neither tears nor drives its teeth through."""

BEASTS = {
    'Sabertooth': dict(
        out='emerald_sabertooth',
        jaw=(0.87, -0.96, None, None),
        P=dict(H=1.238, walk_stride=0.34, walk_lift=0.09, walk_bob=0.008, toe_flex=35, walk_frames=36,
               run_stride=0.8, run_lift=0.17, run_bob=0.02, run_flex=10, run_frames=18, jaw_open=32, lunge=0.2,
               death_belly=0.377, bite_open=55, bite_close=22,
               special='leap', leap_dist=0.6, leap_height=0.24, bite_side=1.0),
    ),
    'Blisterback': dict(
        out='blisterback_ravager',
        jaw=(0.72, -1.11, 0.70, -1.38),
        P=dict(H=1.205, walk_stride=0.36, walk_lift=0.1, walk_bob=0.01, toe_flex=30, walk_frames=38,
               run_stride=0.75, run_lift=0.16, run_bob=0.02, run_flex=8, run_frames=20, jaw_open=30, lunge=0.2,
               death_belly=0.382, run_tail_pitch=8, bite_open=52, bite_close=40,
               special='leap', leap_dist=0.5, leap_height=0.2, bite_side=-1.0),
    ),
    'Spineback': dict(
        out='spineback_terror',
        jaw=(0.46, -1.23, 0.45, -1.48),
        P=dict(H=0.972, walk_stride=0.3, walk_lift=0.08, walk_bob=0.008, toe_flex=30, walk_frames=40,
               run_stride=0.6, run_lift=0.13, run_bob=0.018, run_flex=7, run_frames=20, jaw_open=28, lunge=0.2,
               death_belly=0.273, run_tail_pitch=4, bite_open=50, bite_close=18,
               special='spin', spin_side=1.0, special_frames=60, bite_side=1.0,
               tail_freq_base=2.6, tail_freq_tip=1.5, tail_damping=0.4),
    ),
    # Modelled with the mouth open, so jaw_open is smaller; the tongue is a loose island
    # that goes wholly to the jaw after split_jaw_geodesic.
    'Thornhide': dict(
        out='thornhide_ravager',
        length=2.8,
        rig=dict(front_trace=0.6, hind_trace=0.45, belly=0.42,
                 front_joint_z=0.56, front_knee_z=0.34, front_ankle_z=0.08,
                 hind_joint_z=0.55, hind_knee_z=0.33, hind_ankle_z=0.13,
                 neck_frac=0.4, neck_zmin=0.35, head_zmin=0.3, tail_zmin=0.15, tail_xlim=0.05,
                 tail_bones=6, joint_x_in=0.75),
        jaw=(0.645, -1.12, 0.59, -1.36),
        P=dict(H=1.223, walk_stride=0.36, walk_lift=0.1, walk_bob=0.01, toe_flex=30, walk_frames=38,
               run_stride=0.75, run_lift=0.16, run_bob=0.02, run_flex=8, run_frames=20, jaw_open=22, lunge=0.2,
               death_belly=0.326, run_tail_pitch=8, bite_open=34, bite_close=24,
               special='leap', leap_dist=0.5, leap_height=0.2, bite_side=1.0),
    ),
}
