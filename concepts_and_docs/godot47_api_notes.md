# Godot 4.7.2 API notes

Local companion to the official 4.7 docs. Two purposes:

1. Document the **API deltas / gotchas actually hit in this project** (4.7
   renames that cost the most iterations during the P0 spikes).
2. Explain the **regenerable class-reference cache** under
   `reference/godot47_docs/` and the convention for extending it.

## Class reference cache

- Location: `reference/godot47_docs/` — **gitignored**, never versioned,
  never imported by the game. The notes in this file ARE versioned.
- Format: raw XML dumped from the exact local binary (`class_*.xml` names are
  the class names, e.g. `AnimationNodeBlend2.xml`). Read/Grep-able; much
  faster and more accurate than fetching the web docs.
- The cache only holds the classes needed *so far*. On demand only: when a
  new class is needed, regenerate and keep only the new file(s).

### Regenerate / add a class

```sh
mkdir -p /tmp/godot47_docgen
~/App/Godot/Godot_v4.7.2-stable_linux.x86_64 --headless \
  --doctool /tmp/godot47_docgen
# whole built-in class set lands in /tmp/godot47_docgen/doc/classes/*.xml
# delete the temp dir afterwards; keep per-class file(s) only
```

The `<path>` must already exist. The dump covers the full built-in API of the
4.7.2 binary — no net, no web, version-exact.

### Convention

- **API questions are answered from the cache first** (`Read`/`Grep` the XML),
  not from webfetch. The web is a fallback for tutorials/concepts, never for
  class API facts.
- Members/methods are authoritative in the XML: `<member name="…">`,
  `<method name="…" return="…">`, `<param index="…" name="…" type="…">`.

## 4.7 deltas and gotchas (discovered in the layers spike)

- **Track types renamed to `_3D`**: `Animation.TYPE_POSITION_3D`,
  `TYPE_ROTATION_3D`, `TYPE_SCALE_3D` (old `TYPE_POSITION` etc. are gone).
  `TYPE_BLEND_SHAPE`, `TYPE_METHOD`, `TYPE_BEZIER`, `TYPE_AUDIO`,
  `TYPE_ANIMATION`, `TYPE_VALUE` unchanged. Verified in `Animation.xml`.
- **Markers**: `get_marker_list()` → `get_marker_names()` (PackedStringArray);
  the rest of the marker API (`add_marker`, `get_marker_time`,
  `has_marker`) is unchanged.
- **Interpolation accessors renamed** on Animation:
  `track_get_interpolation()` → `track_get_interpolation_type()`;
  `track_set_interpolation()` → `track_set_interpolation_type()`;
  `track_loop_wrap_enabled()` → `track_get_interpolation_loop_wrap()`;
  `track_set_loop_wrap()` → `track_set_interpolation_loop_wrap()`.
- **`track_set_method_name()` removed.** METHOD tracks carry the callable per
  key — read back with `method_track_get_name(track, key)`. There is no
  generic rename setter anymore; build the desired name at key-add time.
- **`AnimationNodeBlendTree.connect_node()` returns `void`** in 4.7 (was an
  error enum in earlier 4.x). The CONNECTION_* constants no longer signal
  failure; connect and proceed. Signature:
  `connect_node(input_node, input_index, output_node)` — the *output* node
  feeds INTO the *input* node's port.
- **`AnimationNodeBlendTree` auto-creates its `output` node** — do NOT
  `add_node(&"output", …)`; connect your branch to the existing output input
  (port 0):
  `blend_tree.connect_node(&"output", 0, &"blend")`.
- **`AnimationNodeBlend2.amount` is not a member** (verified: no `<member>` in
  the XML). The blend weight is a dynamic tree *parameter*:
  `tree.set("parameters/blend/blend_amount", value)` (read back with `get`).
  `AnimationNodeSync.sync` IS a member: it makes both branches advance —
  required for an upper-layer attack blended over a looping walk (without it,
  at amount=1 the walk branch freezes on its first frame).
- **`Basis` has no `angle_to()`.** Compare orientations with quaternions:
  `a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())`.
- **`const X := preload(...) as Script` is invalid** — a cast is not a
  constant expression. Declare the preload without the cast.
- **`AnimationTree` members** (inherits `active` from `AnimationMixer`):
  `tree_root` holds the `AnimationNodeBlendTree` resource; `anim_player` (not
  `animation_player`) points at the driver `AnimationPlayer`.

## Project usage notes

- Retargeting import-time renames bones to profile names, so animation glm
  tracks (subnames) match the character skeleton 1:1 — `split_body_parts()`
  in the layers spike (`src/tools/spikes/anim_prep.gd`) relies on this.
- **Autoload identifiers are NOT resolvable in standalone `--headless --script`
  compile** (`Identifier not found: GameState`) — that mode never registers
  project autoloads. Validate autoload-referencing scenes by *running* them
  headless:
  `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . scenes/tests/<scene>.tscn`
  (scenes can auto-quit when `DisplayServer.get_name() == "headless"`).

## Lessons from the upper/lower layers spike (FAIL 15/09/2026)

The spike (roadmap:33) was abandoned; these are the verified facts it uncovered:

- **`AnimationNodeBlendTree.root_node` was removed** — the member list is now
  only `graph_offset`; the `output` node is auto-created. To drive the tree,
  connect your branch into the existing output input (port 0).
- **`AnimationNodeBlend2` is a lerp, not an overlay**: `amount` runs
  `walk × (1−amount) + attack × amount` (weights sum to 1). It CANNOT keep two
  disjoint body layers (e.g. lower=walk, upper=attack) at full intensity
  simultaneously. Layering different body parts needs an additive node or
   per-bone masking — a different topology, deferred out of V1 (decision at P2 exit, 21/09/2026).
- **`get_animation_list()` returns `Array[StringName]`** (not `Array[String]`)
  on AnimationLibrary.
- **`event.keycode` is keyboard-layout dependent** (AZERTY digits 1-5 do not
  produce `KEY_1`..`KEY_5` unshifted). Use `event.physical_keycode` (+ numpad
  `KEY_KP_*`) for layout-independent controls.
- Suspicion, not isolated: animations built from scratch with
  `Animation.new()` + `add_track()` + `track_insert_key()` did not drive the
  skeleton in this tree/player setup, while the same data produced via
  `duplicate()` + `remove_track()` played fine. If the split/rebuild pattern
  returns, prefer editing a duplicate.
- `blend.sync` (from `AnimationNodeSync`) makes both inputs advance together,
  which matters when one branch is a one-shot over a loop.