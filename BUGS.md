# SoulMaker — Bug tracker

**Updated**: 2026-09-28
**Base gelée**: `5335dd6` (anim_creator Bake All 30fps + fixes REV 32-41, recettes humaines OK)
**Règle**: pause new features — un bug à la fois, preuve headless ou recette humaine courte par fix. `TODO.md` / `opencode.json` ne sont jamais commités.

Format par entrée : `ID | zone | gravité | symptôme | repro | suspect | statut`.

## ACTIFS (diag en cours)

- **BUG-001 | anim_creator / rig | FIXÉ (recette visuelle en attente) | T-pose : `LeftUpperArm` RigRoot tourné (~90°) vs gltf origine `0 180 0` | Ouvrir `scenes/anim_creator/anim_creator.tscn`, lire l'os | Cause : `_aim_bone` plaque le X local sur l'axe anatomique du coude ; sur les bras le X du bind est ⊥ à cet axe (jambes : ∥, cuisses à 0.00°) → roll axial statique de 90° du solver, constant et symétrique L/R | PROUVÉ headless 28/09 (3 sondes `/tmp/opencode/probe_rest_vs_pose|roll_axis|geo_drift|full_xform.gd`) : rest 65/65 os à 0.00° (asset innocenté) ; seuls `Left/RightUpperArm` bougent (90.00° pile) ; delta recomposé en frame locale `≈ (0.02, 0.71, 0, 0.71)` = 90° pur autour de l'axe long (`ll ≈ (0.03, 1, 0)` — le « swing 90° » de la sonde 2 était une erreur de frame de ma décomposition, l'axe (0.03,±1,0) est local pas monde) ; origines épaule/coude/main exactes à 0.0 mm (points sur l'axe invariants) ; avant-bras à 0.00° (X déjà sur charnière). Contenu : rien en aval ne lit l'orientation du bras (coude chaîné invariant, poignet relatif à l'avant-bras, bake via ancres) → positions/charnière/bake sains. Reste : (a) twist de skin 90° sur le segment bras vs bind (œil humain requis), (b) confusion inspecteur, (c) risque latent si futur code suppose output ≈ rest. FIX 28/09 (`SCRIPT_REV 42`, non committé) : axe de charnière local par os (`_chain_axis` dérivé dans `_derive_base_refs` — Z hauts-bras, X partout ailleurs donc jambes/avant-bras inchangés) + `_aim_bone(..., axis_ref)` + side non-dégénéré. Gates headless : twist bras 90° → 0.00° L/R, 13/13 (repos err 0.00, drag bras err 0.04 flex 35.8 bow>0, drag jambe err 0.00 flex 91.5, reset exact). Recette : ouvrir creator, bras non tordus au repos + drag main → coude plie propre**.

## ANIM_CREATOR (bake / solveurs)

- **BUG-002 | anim_creator bake | MINEUR (connu, par design) | Jitter pieds après bake : ancres sparse portent déjà `0.091 → 0.115` (+24 mm), le bake interpole fidèlement (`densify ≠ plant`) | Re-bake clip crouch 3 clés, lire logs ancres | Lerp linéaire os par os sans contrainte plantés ; mitigé REV 39 `_pin_static_handles` (< 30 mm / < 3°) | SURVEILLÉ — rouvrir si pin insuffisant**.
- **BUG-003 | anim_creator save | MINEUR (documenté) | `authored_pack.res` quantifie micro-rotations (~0.05° pire-cas, positions exactes) | `probe_save.gd` : 390 clés, rot max 0.056° | Même régime que `player_pack.res`, invisible | ACCEPTÉ — seuils gate production à prévoir**.
- **BUG-004 | anim_creator → jeu | OUVERT (design à part) | Promo jeu des clips authorés (slots moveset) non conçue | — | Strip rig `..:position` à l'export (REV 28/29) | À DESIGNER post-chasse**.

## RUNTIME (jeu)

- **BUG-005 | runtime rig_kit | MOYEN (contradiction) | `src/runtime/rig_kit.gd:65-68` : commentaire `NE PAS forcer motion_scale` mais code `skeleton.motion_scale = 1.0` | Lire le fichier | Drift REV 26/29 (revert partiel) | À TRANCHER — un seul propriétaire de motion_scale**.
- **BUG-006 | runtime game-wide | MAJEUR (gelé, décision feel requise) | Import GLTF pose `motion_scale=0.9491` : le mixer scale TOUTES les translations évaluées (~5 % crush takes partout) | Comparer takes jeu vs mètres | Connu depuis REV 25, non touché volontairement | GELÉ — centraliser en `rig_kit` seulement après validation feel humaine**.
- **BUG-007 | runtime combat | À VÉRIFIER (slices non committées à l'époque, vérifier sur HEAD) | Guard turtle regen, chain-break `guard_release_needed`, stamina `10 → 30`, plunge temp-lock, `lock_target` Nil, stick saturate, fall grace, LAND `contact_time 0.1542` | Rejouer harnesses `verify_crab/guard/dodge` sur HEAD | Slices WORKLOG 22-23/09 | À REJOUER**.

## ANIM_LAB / DATA PIPELINE

- **BUG-008 | anim_lab editor | MOYEN | `src/editor_tools/editor_confirm.gd` : `ConfirmationDialog` est `Window` pas `Control` → `custom_minimum_size` ERROR, invisible en `--check-only` | Recette humaine uniquement | API 4.7 | À FIXER avec recette éditeur**.
- **BUG-009 | anim_lab bake | MINEUR | Dérive silencieuse `KNOWN_SLOTS ↔ @export_enum` 16 slots → slot-unknown + warn | `verify_assign` 46/46 en gate | Pas de garde auto | SURVEILLÉ**.
- **BUG-010 | data imports | MINEUR | `.import` gitignorés avec `assets/` : UAL2 a pointé `humanoid_bonemap` au lieu de `character_bonemap` + flags `rename_bones/rest_fixer` incohérents (07:40/09:02/11:53) | Restart froid, comparer générations | Mélange de générations d'import | PROCÉDURE : imports gelés sauf restore ordonné**.
- **BUG-011 | data pipeline | MINEUR | Pas de CI validateurs (ADR-009/015/016 : unknown-fields, runs nommés, `tmp→rename` + quarantaine) ; `player_pack_baker.gd:48` warn `stale entry?` sur rename | — | Vault `features.md:242` | DETTE**.

## ENGINE / OUTILLAGE (quirks actés, à ne pas redécouvrir)

- **Q-001** : `track_remove_key_at_time` sur track vide = `ERROR idx < 0`, pas no-op → `find+set/insert` (B1).
- **Q-002** : `Animation.new()+add_track()+insert_key` ne drive pas tree/player en spike, `duplicate()+remove_track()` oui → préférer duplicate.
- **Q-003** : `pause()` vide `current_animation`, `assigned = ""` invalide, `stop()` vide current + restaure props → état possédé + save/restore rig.
- **Q-004** : `get_bone_global_pose` INCLUT l'override (spin +90°/frame si réappliqué) ; `get_bone_global_pose_no_override` = rest/zéros inutilisable ; reads hors-signal = rest.
- **Q-005** : Pas de `#` dans `.tscn` (casse le parse silencieusement, RigRoot vide). Screenshots illisibles par l'IA ; overlay + logs = pont.
- **Q-006** : `SubViewport.world_3d` reste null malgré `own_world_3d=true` → `camera.get_world_3d()` (`map_editor.gd:492`).
