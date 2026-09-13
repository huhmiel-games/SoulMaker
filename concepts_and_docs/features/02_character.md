# 02 — Character system

> The shared character platform: one skeleton, one animation library, config-driven appearance. Mother of `03_progression` (stats), `04_inventory` (equipment), `05_enemies` (archtypes reuse this). Neutral spec — status lives in `features.md`.

## Standard humanoid skeleton (retargeting)

**Goal** — every character (player, NPC, enemy) animates from the same shared library regardless of its 3D source.
**Behaviors** — all official/community models are retargeted onto `SkeletonProfileHumanoid` (Mixamo-style); sources are contingent (Mixamo, Quaternius, community...) — the license decides, not the format; shared locomotion + melee library plays on any model.
**Parameters / bounds** — exact bone naming normalized at import; profiles verified headless.
**Data / JSON** — no per-world data (rig-owned).
**Interactions** — `10_catalog` (import validation step 5), `06_worlds` (enemy placement), shared animation timings (below).
**Edge cases** — missing bone on a variant (has_method guards on events), scale differences between sources.
**Open questions** — none (decided).
**Sources** — idea.txt 1198-1243, ADR-006.

## Attachment slots (sockets)

**Goal** — equipment snaps to the rig, all same placement (accessories are data-items — **no rig visual**, `04`).
**Behaviors** — attach points on the skeleton (BoneAttachment3D or Marker3D aligned to Blender locators): hair on skull, ears lateral, weapon on hand, cape on back, etc.; locator lives in the base head mesh so all face variants share placement. **Armor pieces bind here too** (helmet/chest/gauntlets/leggings — Armor overlay above).
**Parameters / bounds** — slot ids are canonical (catalog).
**Data / JSON** — character config lists `attachments: [{slot, asset_id}]`; validated at import.
**Interactions** — `04_inventory` (equipment visuals via these slots; accessories are data-only, no slot), `01` combat (weapon presentation during swing).
**Edge cases** — object missing at load (graceful fallback), slot conflict (two capes).
**Open questions** — none.
**Sources** — idea.txt 883-899.

## Morphs / blend shapes (bounded)

**Goal** — expression and silhouette variety from topology-preserving morph targets, no topology change.
**Behaviors** — runtime blend shapes on the skeleton mesh; shape values live on the `Mesh` resource → **per-instance `duplicate()`** needed so enemy clones differ; morph sliders bounded (strict but generous), linked groups (shoulders/torso) to prevent clipping.
**Parameters / bounds** — numeric blended targets; slider bounds and linked-track groups enforced at editor + import.
**Data / JSON** — character config morph map `{shape: value}`.
**Interactions** — `05_enemies` (variety via combinatorics, ADR-007), `13_presentation` (5-10 shapes kept for cutscenes), same base for player/NPC/enemy.
**Edge cases** — morphs past bounds (reject), blend on top of equipment collisions.
**Open questions** — none major.
**Sources** — idea.txt 122-164, 168-172, 186-192, 581-587, 461-466.

## 2D face layers + atlas

**Goal** — the anime face: clean, controlled, expressive via *texture* not geometry.
**Behaviors** — full rigless face; front-unfold UV (VRM-style) mandated from import; base skin + eyes + brows + mouth + accessories in one atlas; parts as quads or swapped textures; runtime shader does UV-offset sampling with **snapped frames** (floor), talk ≈ 5-8 poses at 12fps; eyes/brows/mouth animate via AnimationPlayer track on the shader param.
**Parameters / bounds** — frame snap (no float bleed), pose count ≈5-8 talk poses, UV protected zone keeps geometry sliders from corrupting detail frames; **up to 5 composited overlay layers** per face (hair, brows, beard, scar/paint… — resolved 13/09/2026).
**Data / JSON** — face config: layer ids, atlas offsets, blink set + talk poses choice.
**Interactions** — computation decision (form = morph, detail = texture, geometry-independent — see edge), `13_presentation` (cutscene close-ups use this), ADR-019 (face light treatment keeps the 2D face readable under cel light).
**Edge cases** — conflict geometry-sliders vs fixed frames (→ resolution below), mouth invisible at gameplay distance (helmet is the acceptable escape), two-texture split (face vs body) chosen for long-lived maker.
**Open questions** — atlas packing (face gets 40-50% texel space).
**Sources** — idea.txt 12-52, 425-462, 797-918, 995-1019.

**Frontier decision** — Form vs Detail: **geometry (blend shapes) for shape**, **texture for color/detail**; all-texture morphs rejected. Face = 2 layers: form (hierarchical morphs skull/jaw/eyes/nose/mouth) + detail (composited overlays). No visemes: speech is text-only, the mouth animates a generic talk loop (`08`, resolved 13/09/2026). Sources 905-915, 849-877.

## Texture & material strategy

**Goal** — character rendering stays cheap while faces look great.
**Behaviors** — face material samplers never tile (skin tiles: body texture tiles, **face never tiles**); generic material samplers stay tiled; VRAM-compressed 1024² ≈ 1MB; two-texture split face+body recommended (long-lived maker).
**Parameters / bounds** — ≤10 simultaneous characters (heroes = unique composite, mobs = identical clones via MultiMesh + perimeter tint); material LOD for background NPCs; aggressive caching by config hash.
**Data / JSON** — config hash key (for cache).
**Interactions** — `15_tech` perf budget, `10_catalog` style.
**Edge cases** — draw calls vs textures (the real cost is draw calls/state changes, not texel count).
**Open questions** — none.
**Sources** — idea.txt 1023-1081, 1488-1518.

## Character config JSON (exportable)

**Goal** — a character is a **declarative config** (morphs, paint layers, attachments, talk poses, blink randomizer) that shares/replays across worlds and devices.
**Behaviors** — versioned; graceful fallback on missing assets; importable/exportable pack player-to-player; same config powers player, NPC, enemy.
**Parameters / bounds** — strict validation at import (ADR-009).
**Data / JSON** — full config schema (`data/schema/character_v0.1.json`, fields above), versioned.
**Interactions** — New game flow (`11_ui`), NPC reuse, `10_catalog` validation.
**Edge cases** — missing asset → fallback default, not error.
**Open questions** — none.
**Sources** — idea.txt 913-935, ADR-009.

## Per-instance blend duplication

**Goal** — blend shapes must not share across clones (values live on Mesh resource).
**Behaviors** — `mesh.duplicate()` per instance before applying morph values; essential for enemy variants.
**Parameters / bounds** — duplicated only when needed (perf guard).
**Data / JSON** — none.
**Interactions** — `05_enemies` morph variants.
**Edge cases** — memory growth with many clones → MultiMesh for identical hordes.
**Sources** — idea.txt 186-192, 581-587.

## Shared animation library + timings

**Goal** — one animation set, personal implementation: events (footsteps, impact) are shared points, each character reacts.
**Behaviors** — Call Method tracks are **relative** (relative to scene root), guarded with `has_method`; global callback timings reused; per-character speed via `AnimationPlayer.speed_scale` / `AnimationNode:scale`; velocity-ratio sync so footstep anims match movement.
**Parameters / bounds** — speed scale bounded; sync target = locomotion-velocity ratio.
**Data / JSON** — per-character config may set animation speed.
**Interactions** — `01` (attack timing, upper/lower); inverse, impact SFX fire from global anim callbacks, implemented per character (heavy vs light steps); character-owned `AudioStreamPlayer` reacts to relay signals, keeping anims generic (`12_audio`).
**Edge cases** — resource_local_to_scene as escape hatch only.
**Open questions** — none.
**Sources** — idea.txt 1249-1331, 1309-1327.

## Head shadow (cell look)

**Goal** — cel lighting must not flatten the face: a soft SDF-style head shadow keeps depth.
**Behaviors** — SDF unlit shading override on the head mesh; Genshin-style soft shadow down the face.
**Parameters / bounds** — intensity/direction parameter.
**Data / JSON** — face config optional flag.
**Interactions** — `13_presentation` close-ups.
**Edge cases** — shadow direction vs key light in editor previews.
**Open questions** — none.
**Sources** — idea.txt 933, 1141.

## Clothing layer (painted, fitted)

**Goal** — the character's base look: clothes are *painted* over the body — fitted garments with no clipping, the foundation every overlay (armor, `04`) sits on.
**Behaviors** — a **clothing slot** picks an **outfit texture set** (texture swap on the base body mesh, one shared UV layout — frozen once for all outfits); alpha **scissor** (100% opaque/transparent — no sorting issues); skin painted under holes (ghost-skin pitfall, accepted); **cosmetic only — 0 stats, 0 weight** (the mechanical layer is armor). Clothes are picked when creating the character **and swappable in-game** like any equipment slot. No silhouette change (fitted only) — silhouette-defining gear is a **volume overlay** (capes, armor), not clothing.
**Parameters / bounds** — outfits share the base UV layout; texture-set budget bounded (catalog `clothing` category); layering: clothing under every armor overlay.
**Data / JSON** — clothing slot: `outfit = {texture_set}` (catalog clothing id); default from the character config, instance value in the run's GameState (inventory, `04`).
**Interactions** — `04_inventory` clothing slot, `11_ui` inventory/creation screens, `10_catalog` clothing category.
**Edge cases** — holes visible (documented pitfall), long-lived maker two-texture split (face vs body), outfit missing at load → default set (graceful, ADR-009).
**Open questions** — none (resolved 13/09/2026: fitted = painted clothing; volume = armor/cape/hair/held — the hybrid rule).
**Sources** — idea.txt 1488-1518, 1513-1517 (hybrid rule), ADR-012.

## Armor as 3D overlay (helmet, chest, gauntlets, leggings)

**Goal** — Dark-Souls-style armor pieces as real geometry worn *over* the clothed body — shells that read in silhouette, not paint.
**Behaviors** — each armor piece is a **separate skinned mesh on the same standard skeleton** (ADR-006), bound to a rig socket via `BoneAttachment`/`Marker` (below), toggled by the equipment system (activation by code, `04`); sized as a **shell** around the body with clearance padding so it never clips the clothes/base at the resting pose. Shared skeleton → all shared animations play on armor for free.
**Parameters / bounds** — shell clearance minimum vs the **max-morph** body (fit rule below); triangle/texture bounds per catalog category (`10_catalog`); max 4 armor overlays per character.
**Data / JSON** — armor items = catalog `equipment` meshes referenced by the character config `attachments` (`data/schema/character_v0.1.json`) or by the inventory slots at runtime; stats/weight in `04`.
**Interactions** — sockets (below), clothing layer (under everything), `04` equipment slots + equip load, `10_catalog` bounds, `02` perf budget.
**Edge cases** — armor+clothes clipping at extreme morphs (starter armor preserves topology → no clip; community armor forced-clearance → tiny gaps acceptable), helmet hides the 2D face (the accepted escape, ADR-019).
**Fit rule (morphs)** — **starter-catalog armor is derived from the base mesh topology** → it shares the relevant morph targets and deforms with the body; **community armor is validated at intake as a shell fitted to the median body with a minimum clearance against the max-morph mesh** (fits every bounded morph; a small gap on extreme sliders is accepted).
**Open questions** — none.
**Sources** — idea.txt 1513-1517, 883-899 (sockets), ADR-012.

## Character perf budget

**Goal** — many characters on screen stay cheap on low-end hardware.
**Behaviors** — ≤10 simultaneous unique characters; hordes = identical clones via MultiMesh + containing tint; material LOD for background; config-hash caching of composed textures. Each skinned overlay (armor pieces, cape, held weapon) counts toward the per-character mesh budget — the 4-piece armor is capped in `10_catalog` bounds.
**Parameters / bounds** — 10 unique cap; MultiMesh path for identical; per-zone light cap reference.
**Data / JSON** — none.
**Interactions** — `15_tech` (quality tiers), `05_enemies` (hordes).
**Edge cases** — blend budget ceiling ~ fine for 5-15 enemies; avoid 50+ shapes per mesh.
**Open questions** — none.
**Sources** — idea.txt 1041-1081, 597-599.