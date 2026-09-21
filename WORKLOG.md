# SoulMaker — Worklog & current state

**Updated**: 2026-09-21

## Current thread

- **Objective**: P2 fighter core — 1st enemy archetype `soldier_melee_v1` (sword+shield, capsule placeholder), UNCOMMITTED
- **Expected mode**: build
- Next step: human enemy recipe (below); commit AFTER human OK (not requested yet).
- **Last step done**: flinch rendu faisable A+B (UNCOMMITTED) — `poise_reset_time` 2.5→3.5 (fenêtre double-flanc, JSON+fallback) + facing stagger comportemental (`_turn_suppress` 0.5 s à 0.3× après hit reçu — le soldat "accuse le coup", pas de conflit avec le gel garde). Difficulté validée OK-souls par humain (kill + mort par session, damage 10 gardé). Boot clean 2 scènes. Recette : 1er flanc → il tourne lentement → 2e flanc → `FLINCH` visible.
- **Previous**: wall rebound DS3 committé (`b713efb`) + `planar` hoist fix + cam `spring_length` 2.5 (committés par humain).

## Test recipe (human) — enemy archetype (scene `scenes/tests/enemy_archetype_test.tscn`)

1. Boot: soldat à 16 m, IDLE (pas d'aggro au spawn — avance pour déclencher, activation 14 m). Il marche vers toi (capsule gris-bleu + slab bouclier).
2. Laisse-le arriver (portée 2.2 m) : `WINDUP` — rouge en ~0.7 s. Règle : **strafe pendant le rouge** (tracking lent), dodge ou encaisse (10 dmg, stagger au 3e coup rapproché). Report lisibilité.
3. Bouclier levé en garde (IDLE/CHASE/WINDUP, cône 90°) : frontal = `blocked` + rebound. **Baissé quand il swingue** (STRIKE/RECOVER) : punis la fin de son attaque, ou flanque pendant son windup → dégâts + `hit/hp`, 2 coups flanc rapprochés → `FLINCH` (casse son windup), 6 coups → `KILLED` (reset 4 s). Garde GELÉE (stand-in binaire jusqu'au stat block P3).
4. MMB/R3 : lock-on (marker jaune). Reste immobile pour voir : 2 coups → poise 10, 3e → `[SM] Hurt` stagger → Idle.
5. Flinch = l'interruption poise (lui comme toi) : jauge vidée → attaque annulée + freeze 0.45 s (lui) / 0.5 s (toi). Au P9 ce sera des anims ; ici freeze + flash, le timing est la spec.
6. Labels : joueur `hp/poise`, 2e ligne `soldier ÉTAT hp poise hits`. Report logs + feel.

## Test recipe (human) — round-trip editor ⇄ game

1. Launch → Map editor → open a map (place 1-2 assets if empty, sculpt a mound WITHOUT saving).
2. Start → pause now has SET SPAWN HERE + PLAYTEST rows. SET SPAWN HERE → toast "spawn set".
3. PLAYTEST → game boots ON the live map: unsaved mound present, spawn where set (drop 2 m, lands → Idle). Move/dodge/lock (no cylinder here — FakeEnemy is test-scene only).
4. Esc → back in the editor, map reopened FROM FILE by name. Expected: the unsaved mound is GONE (it only lived in the freed editor + the consumed live dict) — the file is intact. If you SAVE before PLAYTEST, everything persists across the loop.
5. Report: relief/placements identical editor vs game, spawn facing, Esc return, any `[Run]`/`[MapBuilder]` lines, placements walkable or ghost (collision as-authored).


1. Launch (boots the hub now) → Map editor → library → New (or open a map): ground flat gray as before.
2. Press Y (gamepad) or P (keyboard) → floor mode: HUD shows `FLOOR (__,__) h=+0.0` + hint line, crosshair hidden, flat yellow quad = cell cursor.
3. LS/WASD moves the cursor (coords update in HUD). RS up (or Shift+W) raises the hovered cell in 0.5 m steps — a mound grows; RS down digs a pit (down to −8, up to +8, stops at bounds).
4. A/E → toast "floor checkpoint"; sculpt more elsewhere; B/Q → relief snaps back to the checkpoint (toast); Y/P exits (relief kept, crosshair back).
5. Start (or ESC) → pause modal: SAVE → toast + stays in editor; CANCEL → resumes; QUIT (clean) → back to library; reopen → relief + placements back (report if not).
6. Place an asset on a mound → it sits on the relief; grab + move it → its base follows the relief.
7. Relief judged visually (slopes get walked by the real walker at P2, via the editor ⇄ game round-trip).
8. Report: sculpt feel (cursor/height rates too fast/slow?), any visible hitch while holding height, all `[MapEditor]` log lines, relief after reload.

## Test recipe (human) — locomotion step 1 (body-relative rewrite)

Scene: run `scenes/tests/player_controller_test.tscn` (boots straight in, game profile, mouse captured).
1. Boot: log shows `[Player] ready — profile game, body-relative, nodess SM` (+ `[SM] Idle -> Fall -> Idle` only if spawn drops — snap 1.0 normally sticks the landing silently). Character faces AWAY from camera (report if it moonwalks = rig authored -Z, one-line fix).
2. Idle: mouse orbits the camera around the character (both axes, pitch clamped). Character does not turn.
3. Z (étiqueté, = W physique) → `Locomotion`: camera snaps behind, character runs forward (8 m/s, `running`). Release in 1 s with no input → back to `Idle`. Q/D (A/D physiques) strafe left/right — the RIG turns sideways, the body keeps its heading.
4. While running: mouse-X / RS-X TURNS the body (no camera orbit); pitch still live. Tilt LS partiel → `walking` (2.5 m/s), full → `running`.
5. Ramp (right side): climb without sliding; walk off its edge → `Fall` → lands → `Idle`/`Locomotion`.
6. Label top-left: state + speed + floor + anim + profile + raw. Report feel (turn rate? accel? sneak/run thresholds? camera distance?) + all `[Player]`/`[SM]`/`[RigKit]` lines.

## Test recipe (human) — base toon (the look locks here)

1. Open a map with placed assets (dungeon kit): everything 3D renders stepped-cel (banded light/shadow, rim on edges). Relief too. HUD/crosshair/ring/selection = standard (gizmos excluded by decision).
2. Judge cuts/wrap/steepness on YOUR assets (you know flexible_toon): shadow bands clean or muddy? Rim too strong? `shade` defaults to black (= legacy look); lift/tint only if a night/dungeon asks for it. Report values to freeze or adjust.
3. Ambiance cross-check: Dungeon preset + toon = readable (not pitch black)? Clear day + toon = not blown out? Ambient energy still lights (ambient_light_disabled stayed OFF)?
4. Reload the map → toon persists on all placements (override per surface, textures intact).
5. Report: screenshots-worth description (no image input on my side), any `[MapEditor]` error lines, which uniform defaults to freeze.

## Test recipe (human) — ambiance page

1. Boot the editor: viewport looks as before (defaults = old tres + fog off).
2. Start → pause now has 4 rows (SAVE / AMBIANCE / CANCEL / QUIT). AMBIANCE → page titled `AMBIANCE (Default)`: 5 preset rows, 10 value rows, BACK.
3. A/E on `Preset: Dungeon` → viewport goes dark/foggy, title becomes `AMBIANCE (dungeon)`. ←/→ on `Fog depth end` → fog visibly moves; row text updates. A/E on the row → resets to the dungeon value.
4. Adjust anything → title flips to `AMBIANCE (Custom)`. BACK (or B) → pause. QUIT on a dirty map → confirm (ambiance edits count as edits).
5. SAVE → reopen the map → override kept (same look). New map without section → defaults.
6. Report: preset feel (dungeon/misty readable?), adjust steps too coarse/fine?, all `[MapEditor]` lines.

## Test recipe (human) — pause modal

1. In the editor (clean map): Start → `MAP PAUSED` (SAVE / CANCEL / QUIT). CANCEL (or B, or Start again) resumes.
2. SAVE → toast "saved …", stays in editor. Edit (place/move/sculpt) → Start → QUIT → `UNSAVED CHANGES` (QUIT WITHOUT SAVING / CANCEL). CANCEL returns to the pause; WITHOUT SAVING returns to the library without saving.
3. Clean map → QUIT quits directly (no confirm).
4. Grab an asset (or enter floor mode) → Start → pause opens, state kept; CANCEL resumes grab/floor intact.
5. Report: modal readable over the scene, every `[MapEditor]`/`[Menu]` log line, any input leaking through (camera moving behind the modal = bug).

## Test recipe (human) — map menu round-trip

1. Launch the project (boots the menu, not the editor). Arrows/D-pad move the highlight (first row = New).
2. A/E on New → `untitled_01`, straight into the editor (empty map). Place 2 assets, Start → SAVE, Start → QUIT → back to menu, map listed.
3. A/E on the map row → editor reopens WITH the 2 assets (reload works!).
4. X on the row → armed red text ("DELETE ? X / B") → B cancels → X, X deletes (row gone, neighbor selected).
5. Gamepad only, then keyboard only: strict 1:1. Report: rows, highlight, prints, any break.

## Open items / waiting on you

- Live test of the tabbed catalog (recipe above).
- Gamepad live test on the map editor (earlier recipe, overlapping — the D-pad role changed to catalog navigation; SELECTED-state arrow-nudge was dead code and is deleted: arrows browse, grab moves).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026; catalog panel tabbed by category 17/09/2026; camera zoom removed 17/09/2026.
