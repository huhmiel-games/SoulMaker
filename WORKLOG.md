# SoulMaker — Worklog & current state

**Updated**: 2026-09-22

## Current thread

- **Objective**: P3 Combat depth slice (ADR-018) — S4 roll tiers/backstep/plunge DONE (committé `d49b1f1`) + LAND reception DONE (code+bot, UNCOMMITTED).
- **Expected mode**: build
- Next step: recette humaine LAND (ci-dessous) ; commit sur ordre explicite uniquement.
- **Last step done**: S1 guard + retours humains (UNCOMMITTED) — `player_guard.json` (light/medium/great) + `guard_config.gd` ; `StateGuard` + transitions ; `take_hit` block/chip/break ; soldat `hit_stamina_damage` 10 ; harnais bot 13/13 PASS ; slow-mo export ; boot clean 2 scènes. **Fix log humain** : turtle infini (regen 45/s remplissait les blocks entre swings → pas de regen garde levée + `_regen_wait` sur block, 10 hits soldat → BREAK) ; chain-breaks à 0 stamina (garde tenue à travers le BREAK → `guard_release_needed`, re-press obligatoire, harnais 14/14) ; BREAK en 4 coups (soldat `hit_stamina_damage` 10→30, humain 21/09) + juice de lisibilité (impact stack au torse : hitstop+shake+rumble+spark, sinon freeze idle silencieux) ; overlap labels (State écrit 2 lignes dans un rect 1 ligne → rects 16-60/64-88) ; barres graybox HP/stam/enemy (`test_bars.gd` sur les 2 scènes, vrai HUD = P7). **S2 backstab direct** (soldat cobaye, flag `backstab_vulnerable`, boss différé — humain 21/09) : `critical_multiplier` ×1.5, cône ±30°, états IDLE/CHASE/WINDUP/STRIKE/RECOVER, FLINCH/DEAD exclus, `CRIT_IFRAMES` 0.6, harnais 11/11 ; lisibilité crit (humain 21/09, même anim qu'un hit) : hitstop 60f = 1 s + shake ×1.5 sur crit, à affiner avec de vrais ennemis. **S3 blade shove** (joueur uniquement, plan 21/09 : fallback attaque normale, crack = chip + gros poise, pack lourd dmg 22/stam 35/vit ×0.7) : `greatsword_test.json` (même VikingSwordBS ×1.4) + `WeaponConfig` ; `@export weapon_id` + overlay combat (slot garde le clip timing) ; `StateShove` (lunge + fenêtre sweep + recovery 0.6) trigger avant+attaque états neutres ; `soldier.take_shove` (crack vs `_would_block` partagé) ; harnais 13/13.
- **Recette S3** : `enemy_archetype_test.tscn` (greatsword, même modèle ×1.4) — W+LMB de face sur garde levée : `SHOVE CRACK` + FLINCH, pas de rebound ; W+LMB dans le vide : rien (spacing perdu) ; attaque normale sans avant (dmg 22, lente) ; flank/backstab toujours OK.
- **Last step done**: **S4 roll tiers/backstep/plunge** (tranches humain 21/09 : tiers 0.5/4.5/+0 – 0.4/4.0/+0.15 – 0.25/3.0/+0.4, charge = export `equip_load_ratio`, backstep 15/18/22, plunge ennemis seuls, chute > 5 m) : `player_mobility.json` (seuils 0.30/0.70 base-owned) + `MobilityConfig` (FALLBACK = tranches) ; `@export equip_load_ratio` + `roll_tier()/roll_params()/roll_cost()/backstep_cost()/compute_plunge_damage()/compute_fall_damage()/take_fall_damage()` ; `StateRoll` lit le tier (i-frames/vitesse dérivée/anim lente + recovery plantée fat) ; coûts dodge via helpers (4 états) ; `StateFall` capture `fall_start_y` + buffer attaque → `PLUNGE` mid-air dès min_drop 2.0 m (pas d'auto-trigger) ; `StatePlunge` (piqué, sweep `take_plunge` sinon `take_hit`, damage base+8/m cap 40, knockback 1.5, hit 0.4 s / miss 0.9 s, roll-cancel ≥ 0.5 s) ; `soldier.take_plunge` (contourne bouclier, knockback + FLINCH) ; HUD 2e ligne `load/tier/drop` ; harnais `dodge_harness` 36 asserts 0 FAIL ; non-régression guard 14/14 + backstab 11/11 + shove 13/13, audit PASS ; `player_controller_test.tscn` + rampe sud + `PlungeLedge` 6 m à l'aplomb du FakeEnemy.
- **Last step done**: **LAND reception** (humain 22/09 : clip `rig/adventure__hard landing`, UNCOMMITTED) — slot `land_hard` (moveset JSON + KNOWN_SLOTS) ; `StateLand` (planté, clip entier 2.03 s via `land_duration()`, routing GUARD/LOCKON/LOCOMOTION/IDLE miroir de Hurt) ; `StateFall` route LAND si dégâts > 0 (létal = HURT inchangé) ; harnais +6 asserts (slot/duration/enter/hold/vraie chute 6.5 m → LAND hp 77/létal → HURT — 1er jet sync FAIL : `is_on_floor` faux sans frames, passé en vraie chute + `await _run()`) ; bot 55/55 0 FAIL, audit PASS, boot 2 scènes propre. **Suite (humain 22/09 : intro de la take = posture de chute, pieds au sol à 0.1542 s)** : essai simple — LAND entre à `contact_time` via `anim_seek` (pattern roll/backstep) + blend rapide `LAND_ENTER_BLEND` 0.05 (one-shot `anim_blend` consommé par `_resolve_anim`, `_play` gagne un param `blend`) ; `contact_time: 0.1542` dans les phases du slot (défaut 0.0 + validation) ; sortie sur position du clip (`land_finished`, garde timer) ; durée restante 1.88 s ; `Fall` intouché. Bot : `seeks contact` (pos 0.154 exact au 1er run) + `exits idle` via `seek(2.0)` — FAIL intermédiaire instructif : téléport section 11 = corps en l'air, `Idle` retombe en `Fall` en 2 frames → grounding + settle avant `start(LAND)`. 0 FAIL, audit PASS.
- **Recette LAND (humain)** : `player_controller_test.tscn` — rampe sud → ledge 6 m → MARCHER plein nord dans le vide (sans attaque) : log `Fall hard landing` + réception `hard landing` plantée ~2 s puis Idle ; petite chute : rien ; drop sans attaque depuis faible hauteur : Idle direct. Report : la take ressemble à « accroupi qui encaisse » ? Durée trop longue/courte ? Planté lisible ?
- **Recette S4** : `player_controller_test.tscn` — `equip_load_ratio` 0.2/0.5/0.8 (export Player) : roulade fast/mid/fat (lire tier au HUD, fat visiblement taxée), backstep spacing (zéro i-frame), rampe sud → ledge 6 m → traverser, MARCHER (pas courir) plein nord dans le vide + spam LMB mid-fall : `PLUNGE` + hitstop sur FakeEnemy déplacé à (0,0,−5.5), ~1.5 m passé le bord N dans l'axe de chute (fallback `take_hit`, pas de knockback lisible — knockback soldat couvert par bot), drop sans attaque : rien + dégâts chute 6 m ≈ 16 hp, petite chute : rien. Course off = overshoot (physique honnête).
- **Fix log S4 (humain 22/09, UNCOMMITTED)** : fast 4.5→6.0 m (plus lent que le sprint sinon), mid recovery 0.15→0.08 s (blend trop long), fat thud rumble à `FAT_THUD_TIME` 0.45 s (variable à recalibrer sur la vraie anim P4) ; course off-ledge restait en run sans dégâts — cause : grace 0.65 s + `fall_start_y` capturé à l'entrée Fall (4+ m déjà tombés) → `last_ground_y` suivi au sol + `fall_start_y` mesuré depuis lui + catch `falling_fast()` (vy < −4 m/s, ~0.16 s, ne misfire pas sur escaliers ~3 m/s) dans Idle/Locomotion/Guard/LockOn. Bot 39/39, non-régressions vertes, audit PASS.
- **Fix log S4-bis (humain 22/09, UNCOMMITTED)** : stick toujours en run même à légère inclinaison — cause : `_axis` sommait `is_pressed` (vrai dès 0.2 via la source stick du profil) + `left_stick()`, donc tout tilt saturait à 1.0 → nouveau `InputManager.action_value()` (digital = 1.0, stick = proportionnel, chaque device compté une fois), `_axis` = `action_value(pos) − action_value(neg)` (clavier inchange : sature en run ; tilt = walk, plein = run) ; fat recovery 0.4→0.3 s (blend final trop long) ; audit regex étendue à `action_value`. Bot 39/39, S1/S2/S3 0 FAIL, audit PASS, 2 scènes propres.
- **S4 pardon du piqué (humain 22/09, UNCOMMITTED)** : le piqué demandait la lame dans l'axe (MISS systématiques) → forgiveness souls : `reach = max(min_reach 1.5, blade_length` mesurée au sweep, échelle incluse) pilote détection + hitbox ; commit R1 en Fall libre = fake-lock de l'ennemi dessous (planaire < reach, aucun facing = 180°, marker allumé, corps tracké en Fall + Plunge, revalidé chaque tick, **restauré** à l'atterrissage/sortie — jamais de lock surprise ; déjà locké = intact) ; `PlungeCast` (colonne `(reach+1)×3×(reach+1)` centrée, remplace le sweep lame, murs ignorés) → `take_plunge`. Bot 47/47 (acquire dos à l'ennemi, pas d'acquire hors reach, reach suit l'arme 1.5/3.0, connect via cast, restore), S1/S2/S3 0 FAIL, audit PASS. Fix bot : `_reset()` du soldat avant la section 10 (section 6 l'avait tué : collision off).
- **Fix crash free (humain 22/09, UNCOMMITTED)** : piqué free → `Plunge LAND` → `Plunge -> LockOn` → Nil sur `lock_target` (`lock_chest` + `LockOn.enter`) — cause : `_finish` routait LOCKON sur temp-lock valide, puis `exit()` le releasait avant `enter()`. Fix : `_finish` ne route LOCKON que sur lock réel (`and not plunge_temp_lock`), `exit()` reste le seul release ; Fall→HURT déjà sûr (release avant, commentaire tracé) ; blindage `null` dans `LockOn.enter` (release next tick). Bot +1 assert (`no lockon on temp` → IDLE, vérifié FAIL sans le fix). Tête d'ennemi en locké = effet mannequin (blocked, pas de knockback) — reporté, à revoir sur vrai soldat plus tard.
- **Fake lock silencieux (humain 22/09, UNCOMMITTED)** : le temp-lock allumait le marker de lock-on puis l'éteignait — visuel parasite → `acquire` ne touche plus au marker (tracking purement interne), `release` garde son clear en sécurité no-op. Bot +1 assert (`temp silent` : LockMarker caché sous temp-lock). 49/49, S1/S2/S3 0 FAIL, audit PASS.
- **Last step done**: anim-lab promu en outil durable (UNCOMMITTED) — `scenes/tests/anim_lab*` → `scenes/anim_lab/` (`anim_lab.tscn` + `mount` + `lib.res` + nouveau `anim_lab_tools.gd` + `anim_lab_hidden.json`) ; `.gitignore` ne ignore plus que le `.res` régénérable ; 1 seul bouton inspecteur « Hide current take » (`@export_tool_button`, prend `LabPlayer.current/assigned_animation`, append JSON + `remove_animation` live + re-save `.res`, warning si clip de slot) ; `bake_anim_lab.gd` filtre le JSON + warning slots. Validé : parse 3 scripts, bake 124, round-trip `melee__X Bot` caché → 123 → restauré → 124, boot scène headless exit 0 zéro erreur. **Fix humain** : `LabPlayer` invisible dans le dock (enfant de l'instance `RigRoot`, éditeur les masque sans Editable Children) + chemin exporté fragile → résolution dynamique (`_find_lab_player` cherche l'`AnimationPlayer` portant la lib `rig` depuis la racine éditée, export supprimé) + diagnostic `_ready` (`player OK, N takes`) ; flux réel prouvé headless (`play` + `hide_current_take` → 123 + JSON). **Suite** : le dock retombait en tête de liste après un hide → `_next_take` positionne `assigned_animation` + `play` sur la suivante (précédente si dernière), prouvé headless (`idle (3)` → `now showing 'idle (4)'`, entrée de sonde retirée, 6 hides utilisateur conservés → bake 118). **Suite** : labo ouvert aux 5 autres `.glb` (UNCOMMITTED) — `anim_lab_packs.json` (female/greatsword/torch/various/various2, labo-only, jeu inchangé = toujours les 3 packs du moveset) fusionnés au bake + tally par pack ; bake 217 − 53 hidden utilisateur = 164 (`adventure 12, aerial 14, female 12, greatsword 51, melee 45, torch 1, various2 5, various 24`), zéro warning slot/collision. **Suite** : player pack `.res` + bouton Export (UNCOMMITTED) — `PlayerPackBaker` (merge moveset+labo − hidden, noms `pack__take` inchangés) mutualisé par `bake_anim_lab` + `bake_player_pack` headless ; bouton « Export player pack » dans LabTools ; `RigKit.mount_packed` + `_build_anim_player` (pack → mount direct, sinon rebuild silencieux, corrupt → warning+rebuild) ; pack gitignoré. Validé : checks OK, pack 164, boot `mounted packed anims (164)` + 7 slots identiques, fallback rebuild 124 exit 0, harnais S4 0 FAIL, audit PASS.
- **Last step done**: P3 kickoff (UNCOMMITTED) — coupes kick/parry/riposte→V2 tracées (`features/17`, `features.md`, `roadmap.md` P3/vault/open-items) ; backstab = crit direct positionnel (±30°/0.6 s → ×1.5-×2 immédiat, pas de stance) ; guard break V1 = extended punish stagger (1.2 s + no regen 1.0 s) ; blade shove = heavies seules (2 m, 60-80, recovery 0.6 s + lunge), no-op sur lights (réponse turtles = chip + backstab) ; `parry_window` réservé (0 en V1).
- **Starter numbers proposés (gris, tunables par slice)** : shields light/medium/great = absorb 75/90/100 %, stability ×1.5/×1.0/×0.6, arc 60/75/90° ; `hit_stamina_damage` baseline = damage ×1.0 ; roll tiers fast/mid/fat = i-frames 0.4/0.3/0.2 s, distance 3.2/2.8/2.2 m ; bow 3 charges (0.5/1.0/1.5 s → ×0.7/×1.0/×1.4), crossbow reload = recovery fixe, projectiles 25-35 m/s range 30 m ; status bleed 15 % maxHP burst, poison 2 %/tick ×8, frost slow 15 % 10 s + intake +20 %, meters player/soldier/boss 100/60/200, decay 5/s ; hyper-armor light/medium/heavy 0/8/16 f ; plunge seuil 3 m, cap ×2 ; two-hand ×1.5 verrouillé.
- **Slices P3 (chaque = harnais bot headless + recette slow-mo + commit sur ordre)** : S1 block/guard core → S2 backstab → S3 blade shove → S4 roll tiers/backstep/plunge → S5 ranged graybox → S6 damage types + status → S7 buff engine + two-hand + torch + ladders.
- **Testabilité (leçon P2 graybox)** : slow-mo = export var de scène de test (pas d'input — profil game gelé, audit untouched) ; aucun système fini sans ses 2 preuves (bot + feel).
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
