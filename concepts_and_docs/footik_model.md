# Foot IK model (spike #3)

Minimal foot-placement system for elevated surfaces.
**File**: `scenes/spikes/footik_test.gd` + `scenes/spikes/footik_test.tscn`
**Status**: FAIL — spike abandonné 15/09/2026 (orientation du perso + rig non inspectable dans l'éditeur).

## Constants

| Name | Value | Meaning |
|---|---|---|
| `SOLE_OFFSET` | 0.08 | vertical distance from ankle bone to sole in neutral pose |
| `STEP_HEIGHT` | 0.2 | max rise per foot (adjustable at runtime: PgUp/PgDn) |
| `PLANT_HOLD` | 0.06 | half-width of the plant band (hysteresis) |
| `DESCEND_RANGE` | 0.25 | max gap above ground at which descending velocity counts |
| `STEP_PULL_MAX` | 0.22 | max upward pull applied to a swinging foot toward an elevated surface |
| `WALK_SPEED` | 1.2 | walk forward speed |

## Per-foot state

Each foot maintains: `gap` (sole above ground), `vel` (gap derivative), `phase`, `influence_target`.

## Phase decision (per foot, per frame)

```
idle latched + elevated surface + gap not too negative  → PLANT  (influence → 1)
gap < -PLANT_HOLD                                       → SWING  (influence → 0)
gap <  PLANT_HOLD                                       → PLANT  (influence → 1)
vel < 0  AND  gap < DESCEND_RANGE                       → DESCEND(influence → 1)
otherwise                                               → SWING  (influence → 0)
```

## Target positioning

- **Surface Y** = `ground_y + SOLE_OFFSET`
- **Pulled Y** = clamp `local_foot.y` to `[surface_y, local_foot.y + STEP_PULL_MAX]` — allows partial pull-up to an elevated surface without exceeding a fixed reach per frame (anti-fold).
- **PLANT**: `target.y = surface_y`, `influence → 1`
- **DESCEND**: `target.y = pulled_y`, `influence → 1`
- **SWING**: `target.y = pulled_y`, `influence → 0`

Influence is smoothed exponentially per frame (exp-lerp, half-life ~300 ms).

## Idle latch (stop on step)

When a foot is PLANT with `ground > 0.1` for **2 consecutive frames**, the character:
1. Plays `IDLE_ANIM`
2. Sets `_idle_latched = true` — all feet now use the PLANT rule regardless of descent velocity, pulling them onto the step surface.

Reset via UP key (re-enables walk).

## Anti-fold explanation

The fold (calf pinching under thigh) was caused by the IK target chasing the walk animation while influence was nonzero. The three-part fix:

1. **Bounded target**: `pulled_y` is clamped to `local + STEP_PULL_MAX`, limiting how far the foot is pulled toward a steep surface per frame.
2. **Zero influence in SWING**: IK has no effect while the leg is in the air; it only begins engaging when the foot approaches plant.
3. **Idle pull-up is bounded**: the same `STEP_PULL_MAX` clamp applies, so idle feet never jump instantaneously to the step top.

## Solver setup

- **TwoBoneIK3D** per leg: lower leg → upper leg, target = child of skeleton.
- **Pole target** anchored at `hip_local + Vector3(0, -0.1, 0.6)` — avoids feedback loop of poleing to the knee (which the solver already constrains).

## Important Godot 4.7 rule

A `SkeletonModifier3D` post-IK pose is only readable inside the `modification_processed` signal. Any read outside the signal returns the **pre-IK (animation-only) cache**.

## Validation

> Status note (15/09/2026): results below are **pre-abandon** — the spike is FAIL; the claims must be re-validated if the spike is retried.

`src/tools/spikes/footik_validate.gd` runs 300 frames headless, reports max penetration (foot below ground). Threshold: 0.06 m (half a sole). Without IK the feet sink ~0.11 m; with IK: 0.000 m.
