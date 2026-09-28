@tool
extends Node3D

## AnimCreator — authoring-rig scaffold, hands + wrist, feet + ankle.
##
## DOCTRINE (human 25/09, after a day of fighting steerable planes): the rig
## CONSTRAINS, the user places. Poles stay automatic (plane pinned); knee
## handles add a BOUNDED offset (steering inside the pinned plane — 25/09 :
## placer le genou, pas rouler la cuisse). One custom analytic solver per
## limb (stateless + explicit anatomical branch — TwoBone prouvé bistable
## sur cuisse ET bras : nudge 5 mm = flip 140° permanent, err 21 mm latchée
## post-unload sur bras), honest stretch past reach, wrist/ankle/
## torso/head toggles for the extremities. The user places 9 handles (2
## hands, 2 feet, hips, torso, head, 2 knees); every other pose must be
## anatomically valid by construction (impossible poses are refused by the
## plane/limits, never authored).
## Auto-pole rule (same pre-pipeline slot as the hips follow): pole = chain
## root world pos + fixed anatomical offset (elbows down-back, knees forward)
## + bounded knee-handle offset (legs).
## Internal Node3Ds, invisible, never user-touched — the trace logs their
## positions so the constraint stays observable. Torso handle = deferred.
## Step 2 wrist follow is CODE-DRIVEN (global-pose override, relative mode):
## CopyTransformModifier3D proved fully inert in 4.7.2 — node AND bone
## references, minimal code-built skeleton, both pose channels, every flag
## combo (axes/all, additive, absolute path, child order) — it processes
## (signal fires) but never writes. So the tool applies the handle's
## relative rotation itself each frame: rest cube = zero offset, turned
## cube = poignée/revers at the wrist. The override wins non-destructively
## and reads back through get_bone_global_pose (bake-safe, 1-frame lag in
## live preview — invisible in the editor).
## Twist/disperser verdicts superseded 25/09 (constraint doctrine): TwoBone /
## FABRIK / disperser all stay in the spike as reference — this tool builds
## only TwoBone + auto-pole, every feature written once.
## No InputManager, no key/mouse polling: this is an editor @tool scene
## (like anim_lab), not an in-game editor — the editor viewport IS the UI.
## Metrics publish to StateLabel (Label3D, editor-visible) + ready print.
## Validator seam (tracking_error/elbow_dot/elbow_flexion/hand_bone_quat/...)
## mirrors the arm spike for the future bake guard (step 5).
##
## API note (REV 23) : plus aucun SkeletonModifier3D runtime — solves customs
## (loi des cosinus + _aim_bone) + overrides directs. Le spike arm_ik_test
## garde les références TwoBone/FABRIK. Label3D props vérifiées dans
## reference/godot47_docs/*.xml.
const ARM_BONES := {
	&"Left": {"upper": &"LeftUpperArm", "middle": &"LeftLowerArm", "end": &"LeftHand", "shoulder": &"LeftShoulder"},
	&"Right": {"upper": &"RightUpperArm", "middle": &"RightLowerArm", "end": &"RightHand", "shoulder": &"RightShoulder"},
}
## Legs: TwoBone root = thigh, hip reference = Hips (shared, never overridden).
const LEG_BONES := {
	&"LeftLeg": {"upper": &"LeftUpperLeg", "middle": &"LeftLowerLeg", "end": &"LeftFoot", "shoulder": &"Hips"},
	&"RightLeg": {"upper": &"RightUpperLeg", "middle": &"RightLowerLeg", "end": &"RightFoot", "shoulder": &"Hips"},
}
## Per-limb scaffold wiring (user handle + joint word). Poles AND solver
## targets are INTERNAL (auto-placed / eased, invisible) — the only user nodes
## are handles + HipsHandle.
const LIMB_NODES := {
	&"Left": {"handle": &"LeftHandle", "joint": "elbow"},
	&"Right": {"handle": &"RightHandle", "joint": "elbow"},
	&"LeftLeg": {"handle": &"LeftFootHandle", "joint": "knee"},
	&"RightLeg": {"handle": &"RightFootHandle", "joint": "knee"},
}
## Max input speed, m/s (slew, re-added 25/09): TwoBone twist is a MOTION
## TRANSIENT (measured: fast target jumps excite up to ~180° thigh roll that
## decays over tens of static frames; static holds settle clean). Capping
## per-frame input jumps keeps transients invisible; static poses always
## settle exact. Rubber-bands violent flicks; Reset animates smooth.
const SLEW_SPEED := 1.5
## Anatomical pole DIRECTIONS (world space — elbows behind, knees forward)
## + distance. The direction is re-projected perpendicular to the live
## root→target line every frame (see _update_auto_poles): a rest-anchored
## pole lets the line rotate onto it on large excursions (measured 25/09:
## foot +60 cm crouched → pole 2 cm off the line → degenerate plane → knee
## flips backward/forward at random, bow -167 with dot +0.83). The torso never
## rotates in this rig; revisit if a torso handle lands.
const ARM_POLE_DIR := Vector3(0, 0, -1)
const LEG_POLE_DIR := Vector3(0, 0, 1)
const POLE_DIST := 0.45
## Lateral pole bias for LEGS (25/09): TwoBone rolls the thigh ~180° when it
## aims forward because the forward pole goes parallel to the thigh axis
## (roll reference degenerate — plane stays perfect, bow +252, but the bone
## spins). A lateral component keeps the pole off the thigh axis in all
## sagittal motions (thighs never leave the YZ plane). Mirrored per side
## (outward). Small on purpose: knees must still track forward over the toes.
const LEG_POLE_LAT := 0.0
const LIMB_ORDER := [&"Left", &"Right", &"LeftLeg", &"RightLeg"]
const FLEX_WARN := 150.0

## Solver: TwoBoneIK3D + auto-pole on all four limbs. No tuning, no switch,
## no disperser (dropped 25/09 — its roll problem was FABRIK-specific; one
## line re-adds it if the wrist regresses).
## Wrist orientation follow (step 2 gate): the handle's relative rotation
## (vs its rest) is applied onto the hand bone as a global-pose override.
## Toggle = A/B proof (off clears the override, hand falls back to solver).
@export var wrist_copy := true:
	set(v):
		wrist_copy = v
		_apply_override_clear()
## Ankle orientation (step 3b gate): TwoBone positions the leg but leaves the
## foot orientation to the chain (measured: crouch+step yawed the toes 180°
## backward) — so the foot is WORLD-FLAT by default (rest orientation,
## authored once per take via the cube delta on top), like a planted foot.
## Toggle = A/B proof (off = raw chain orientation).
@export var ankle_copy := true:
	set(v):
		ankle_copy = v
		_apply_override_clear()
## Torso authoring (phase 1, 25/09 : full-manuel — dos/cou/tête posés à la
## main, pas portés par une take) : la rotation du TorsoHandle se répartit
## sur la colonne (Spine 0.2 / Chest 0.3 / UpperChest 0.5, somme 1.0).
## Statique (refs rest au build, le rig ne fait que translater) + translation
## du handle ignorée (le corps bouge via hanches). Toggle = A/B proof.
@export var torso_copy := true:
	set(v):
		torso_copy = v
		_apply_override_clear()
## Head authoring (même pattern) : Neck 1/3 + Head 2/3 du delta du HeadHandle.
@export var head_copy := true:
	set(v):
		head_copy = v
		_apply_override_clear()
## Knee steering (phase 2, 25/09 : placer le GENOU, pas rouler la cuisse) :
## le handle genou décale le pôle auto (offset borné, même direction) — le
## genou suit dans son cercle anatomique, plan/reach/côté toujours contraints.
## Zéro = pôle auto pur (parité exacte). Toggle = A/B proof.
@export var knee_copy := true:
	set(v):
		knee_copy = v
		_apply_override_clear()
## Pelvis authoring (25/09 : bascule/torsion du bassin — tout penché réaliste
## commence là) : la rotation du handle hanches oriente l'os Hips (la
## translation suit le rig comme avant). Jambes + dos partent du bassin
## RÉSOLU (threadé, même pattern que la chaîne dos). Toggle = A/B proof.
@export var pelvis_copy := true:
	set(v):
		pelvis_copy = v
		_apply_override_clear()
## Take underneath (adaptation-first, carte de propriété 25/09) : nom d'une
## Sélection take = le dock Animation du PreviewPlayer persistant (choisir
## l'anim, scrubber le playhead). Les exports ci-dessous sont des MIROIRS
## (gardés pour sondes/headless) : les écrire pilote le player, le dock les
## met à jour en retour. Quand une take est chargée (même pausée), solveurs
## + writers s'effacent (règle unique) — rien ne touche la take affichée.
## Set-as-base fige la pose gelée en défaut ; Unload preview abandonne.
@export var take_name := "":
	set(v):
		take_name = v
		_take_want = not String(take_name).is_empty()
		if not String(take_name).is_empty():
			_last_release = &""
		_apply_take_state()
@export var take_playing := false:
	set(v):
		take_playing = v
		if v and not String(take_name).is_empty():
			_take_want = true
			_last_release = &""
		_apply_take_state()
## Frame de preview (60 fps) : appliquée en pause (précision d'échantillon).
@export var take_frame := 0:
	set(v):
		take_frame = maxi(v, 0)
		if not String(take_name).is_empty():
			_take_want = true
			_last_release = &""
		_apply_take_state()
@export_tool_button("Set as base") var base_action: Callable = set_as_base
@export_tool_button("T-pose base") var tpose_action: Callable = set_tpose_base
@export_tool_button("Unload preview") var unload_action: Callable = _unload_take
## Keyframing authored (Phase B, 27/09) : la pose VISIBLE (writers ou take
## figée) est cléée en local (parent-1 × global, skeleton space, delta rig
## baké — régime takes-style) dans un clip de la lib "authored" (chemins
## GeneralSkeleton:Os, comme les takes) — 2 tracks par os (pos+rot), STANDARD :
## rejouable jeu/Blender sans le creator, capsule-safe.
## Découpage dock/inspecteur (décision humain) : le DOCK transporte (choisir,
## créer, play/loop/scrub, longueur) ; l'INSPECTEUR ponte (Set-as-base, Key
## pose = pose solvée→tracks, Edit = gel→base, New = placement lib,
## authored_time = temps de clé, jamais miroir).
## États (possédés par le tool, mutuellement exclusifs) : WRITERS = aucun
## preview (solveurs+writers drivent) ; TAKE = takes/X adopté (player drive,
## writers effacés) ; AUTHORED = authored/Y adopté (player drive, writers
## effacés). authored_time = le temps de travail : temps de clé en WRITERS,
## position de scrub (écrire = seek si authored chargé + pausé) en AUTHORED.
@export var authored_clip := "pose_01"
@export var authored_time := 0.0:
	set(v):
		authored_time = maxf(v, 0.0)
		_apply_authored_state()
@export var authored_length := 2.0
@export_tool_button("Key pose") var key_action: Callable = key_pose
@export_tool_button("Edit authored") var edit_authored_action: Callable = edit_authored
@export_tool_button("New clip") var new_clip_action: Callable = new_authored_clip
@export_tool_button("Save authored") var save_authored_action: Callable = save_authored
@export_tool_button("Bake All (30fps)") var bake_all_action: Callable = bake_transition_all
## Pose de défaut (T-pose rest ou take figée) : LA source unique — tous les
## writers lisent les refs dérivées de ce dict, jamais le bind ni le live.
## Session-only (pas sauvée) ; Reset handles ne la touche pas.
var _base_pose := {}
var _base_name := "T-pose"
var _pending_base := false
## Os authorés (tout le reste suit la base en statique).
var _authored_names: Array = []
## Baked take library (le MÊME player_pack.res que le labo monte — une
## source, labo et jeu toujours en sync). Fichier local ignoré (assets/).
const TAKE_PACK := "res://scenes/anim_lab/player_pack.res"
## Max user pole offset (plane health: l'auto-pôle est à 0.45, l'offset ne
## peut pas le ramener sur la ligne — pas de dégénérescence possible).
const KNEE_OFF_MAX := 0.3
## Spine chain + authoring fractions (noms Superhero, sondés au build).
const TORSO_SPLIT := [[&"Spine", 0.2], [&"Chest", 0.3], [&"UpperChest", 0.5]]
const HEAD_SPLIT := [[&"Neck", 1.0 / 3.0], [&"Head", 2.0 / 3.0]]
## Diagnosis trace (human 25/09: overlay unreadable, paste Output instead) —
## prints a timestamped snapshot line ONLY on change (handle/pole moved, hips
## moved, or metric transition — throttled to 4 Hz during drags), plus an
## immediate EVENT line on every ok↔INV transition. Paste the lines here
## for analysis. show_label re-enables the old Label3D overlay.
@export var trace_log := true
@export var show_label := false
## Min interval between change-snaps (spam guard during continuous drags).
const TRACE_MIN_INTERVAL := 0.25
@export_tool_button("Reset handles") var reset_action: Callable = reset_handles

var _skeleton: Skeleton3D
var _handles := {}
## Code version printed at ready — stale-cache insurance (25/09: rapid
## edit/run cycles served mixed bytecode; if the printed REV isn't the
## latest, the run is void — reload).
const SCRIPT_REV := 41
## Auto-pole nodes (internal, invisible, created at build — never scene nodes,
## never user-touched; re-created on every _build, old ones freed).
var _poles := {}
## Solver-target proxies (internal, invisible): les solves customs lisent
## ceux-ci, ils easent vers les handles à SLEW_SPEED. Snappés au build ;
## freed/re-created avec les pôles.
var _proxy := {}
## Body handle (HipsHandle): drags the whole RigRoot so planted feet stay
## planted while the body moves (translation only). Scene-space rest + node.
var _hips: Node3D
var _hips_rest := Vector3.ZERO
## Rig-follow goal constant (world): handle − rig ancré aux moments
## atomiques (build / capture / reset). L'ancien goal utilisait _hips_rest
## (ancre repos) : après un Set-as-base depuis une take, le handle snappé
## sur les hanches take faisait chasser le rig d'un delta post-capture, les
## membres re-solvant autour d'un frame translaté (flex/bow dérivés).
var _hips_goal_off := Vector3.ZERO
## RigRoot au repos (capturé au build) : frame de référence des clips
## authored (27/09 : régime takes-style — la translation du bassin est bakée
## dans l'os Hips au key, le rig reste ici en lecture ; workflow Reset-first :
## la scène se rouvre au repos, comme les handles).
var _rig_rest := Vector3.ZERO
var _hips_rest_rot := Quaternion()
var _hips_rest_w := Quaternion()
## Bassin résolu (monde, ce frame) : orientation = repos × delta handle
## (identité si toggle off), position = live (rotation sur place).
## Jambes + dos + pôles partent d'ici, jamais du repos.
var _hips_sq := Quaternion()
var _hips_sp := Vector3.ZERO
## Offset rest-local hanches→haut-cuisse par jambe (le tilt du bassin
## déplace le haut des cuisses — threadé dans solveur + pôles).
var _hip_off := {}
var _label: Label3D
var _handle_rest_rot := {&"Left": Quaternion(), &"Right": Quaternion()}
## Torso/head authoring handles (rotation seule) + refs rest statiques
## (scene-space pos + rest-rot du handle, orientation/origine monde des os).
var _torso: Node3D
var _head: Node3D
var _torso_rest_pos := Vector3.ZERO
var _head_rest_pos := Vector3.ZERO
var _torso_rest_rot := Quaternion()
var _head_rest_rot := Quaternion()
var _spine_rest := {}
## Follow offsets (le cube reste sur l'os quand le corps bouge : handle_rest
## − os_rest au build ; rotation authored intacte, position réécrite).
var _head_follow_off := Vector3.ZERO
var _torso_follow_off := Vector3.ZERO
var _spine_solved_pos := {}
## Dernières positions écrites par le follow (25/09 : si le handle est
## ailleurs, c'est l'humain qui l'a bougé dans l'éditeur — on adopte son
## placement comme nouvel offset au lieu de l'écraser).
var _head_last_follow := Vector3.ZERO
var _torso_last_follow := Vector3.ZERO
var _follow_init := false
## Knee steering handles (rotation ignorée, position = offset du pôle auto).
var _knee := {}
var _knee_rest_pos := {}
## Pole seed direction per limb (skeleton space, capturé au Set-as-base) :
## le solveur replace le coude/genou dans le plan (racine→cible, pôle) —
## avec la direction anatomique générique, une take dévie du plan authoré
## de ~1 cm (coude, walking f20 mesuré 9.58 mm). En capturant le côté de
## pli RÉEL de la pose (take ou travail), le re-fit est exact par
## construction (même triangle : mêmes longueurs, même angle, même plan).
## Jambes/takes normales ≈ anatomique ; membre quasi-tendu (e_perp < 1 cm)
## ou T-pose → anatomique (clé effacée). Le verrou anti-flip (bend vs
## _chain_bend_ref) est inchangé : un côté pathologique retombe sur
## l'anatomique, jamais de flip.
var _pole_dir_cap := {}
## Fresh solver snapshot per side (written by _solve_arm/_solve_leg same frame).
var _solve_pos := {}
var _solve_fore := {}
var _rest := {}
var _joint_rest := {}
var _shoulder_rest := {}
var _upper_rest := {}
var _reach := {}
## Expected bow direction per limb (skeleton space, from initial pole pos):
## the joint must stay on the pole side of the root→end line; crossing it =
## backward bend (invisible to the dot metric on quasi-straight limbs).
var _bow_ref := {}
var _err := {&"Left": 0.0, &"Right": 0.0, &"LeftLeg": 0.0, &"RightLeg": 0.0}
var _dot := {&"Left": 1.0, &"Right": 1.0, &"LeftLeg": 1.0, &"RightLeg": 1.0}
var _flex := {&"Left": 0.0, &"Right": 0.0, &"LeftLeg": 0.0, &"RightLeg": 0.0}
var _prox := {&"Left": 0.0, &"Right": 0.0, &"LeftLeg": 0.0, &"RightLeg": 0.0}
var _bow := {&"Left": 0.0, &"Right": 0.0, &"LeftLeg": 0.0, &"RightLeg": 0.0}
var _built := false
var _warned := false
var _trace_accum := 1.0
var _trace_elapsed := 0.0
var _flag := {&"Left": "ok", &"Right": "ok", &"LeftLeg": "ok", &"RightLeg": "ok"}
var _label_cleared := false
## Last printed change-signature (mm/deg ints): hips offset + per limb
## handle pos/rot + pole pos. Compared each frame — silence when idle.
var _trace_key: Array = []
## Fresh end-bone world orientation per limb (main = writer poignet, pied =
## solveur custom ; _process reads verraient le rest — cf. leçon pipeline).
var _solve_end := {}
## Fresh thigh/upper-arm world orientation per limb (same slot — hip-fold and
## thigh-roll diagnosis, future bake guard).
var _solve_upper := {}
var _solve_middle := {}
## Foot rest world orientation per leg (ankle reference — static, captured at
## build; the rig only ever translates so it stays valid for the session).
var _ankle_rest := {}
## Hand rest-local (parent × main) DÉRIVÉ DE LA BASE (take figée ou repos) :
## le writer poignet utilisait le rest bind — après un Set-as-base la main
## reprenait l'orientation bind-relative au lieu de la take (décalage).
var _wrist_rest_local := {}
## Custom analytic solver refs, 4 membres (REV 23 : TwoBoneIK3D prouvé
## bistable jambes ET bras — nudge 5 mm = flip 140° permanent, err 21 mm
## latchée post-unload bras). Le solveur custom est STATELESS (pur fonction
## des inputs) + branche EXPLICITE (côté anatomique imposé, roll minimal vs
## rest) : le flip est impossible par construction.
## Per limb: L1/L2 lengths, rest world orients (upper/middle/end),
## rest-local length dirs, constant bend-side ref (world). Dérivés de
## _base_pose (rebase à chaque Set-as-base).
var _chain_len := {}
var _chain_rest_w := {}
var _chain_len_local := {}
var _chain_bend_ref := {}
var _chain_side := {}
## Arm root chain hops (per arm, base-derived — see _derive_base_refs).
var _arm_hop := {}
## Solved spine orientations (world, same frame — _apply_spine runs before
## the limb solves; arms compose their root from these).
var _spine_solved_quat := {}


## Limb table lookup (arms vs legs share every solver feature).
func _bones_of(limb: StringName) -> Dictionary:
	if ARM_BONES.has(limb):
		return ARM_BONES[limb]
	return LEG_BONES.get(limb, {})


func _ready() -> void:
	_build()


## Idempotent build (editor re-entry safe): clears runtime modifiers, then
## resolves the skeleton + scene handles and stacks the solvers on them.
## Handles are NEVER moved here — the .tscn holds probed rest defaults and
## the human owns them via the gizmo (Reset button re-snaps on demand).
func _build() -> void:
	_skeleton = _find_skeleton()
	_label = get_node_or_null("StateLabel") as Label3D
	if _skeleton == null:
		if not _warned:
			_warned = true
			push_warning("[AnimCreator] skeleton not resolved (RigRoot asset missing?)")
		if _label != null:
			_label.text = "AnimCreator: skeleton missing"
		return
	# Unit space : NE PAS forcer motion_scale ici (ni labo ni jeu — leçon
	# 27/09 : l'import GLTF règle 0.9491 et le mixer scale les translations
	# évaluées ; forcer 1.0 décollait les takes du sol de ~5%. La valeur
	# importée fait foi tant que creator/labo/jeu la partagent — le round-trip
	# key/play est exact à valeur constante, quelle qu'elle soit).
	_clear_modifiers()
	_clear_auto_poles()
	_hips = get_node_or_null("HipsHandle") as Node3D
	if _hips == null:
		push_error("[AnimCreator] HipsHandle node missing in scaffold")
		return
	_hips_rest = _hips.global_position
	_hips_rest_rot = _hips.global_transform.basis.get_rotation_quaternion()
	var _rig0 := get_node_or_null("RigRoot") as Node3D
	if _rig0 != null:
		_hips_goal_off = _hips.global_position - _rig0.global_position
		_rig_rest = _rig0.global_position
	# Base = repos (bind) + refs dérivées — source unique des writers.
	_capture_rest_base()
	_derive_base_refs()
	_build_authored_set()
	_torso = get_node_or_null("TorsoHandle") as Node3D
	_head = get_node_or_null("HeadHandle") as Node3D
	if _torso == null or _head == null:
		push_error("[AnimCreator] TorsoHandle/HeadHandle node missing in scaffold")
		return
	_torso_rest_pos = _torso.global_position
	_head_rest_pos = _head.global_position
	_torso_rest_rot = _torso.global_transform.basis.get_rotation_quaternion()
	_head_rest_rot = _head.global_transform.basis.get_rotation_quaternion()
	# Follow offsets (positions monde au build — rig au repos ici).
	_torso_follow_off = _torso_rest_pos - _skeleton.to_global(_skeleton.get_bone_global_pose(_skeleton.find_bone(&"UpperChest")).origin)
	_head_follow_off = _head_rest_pos - _skeleton.to_global(_skeleton.get_bone_global_pose(_skeleton.find_bone(&"Head")).origin)
	for leg in LEG_BONES:
		var kh := get_node_or_null("LeftKneeHandle" if leg == &"LeftLeg" else "RightKneeHandle") as Node3D
		if kh == null:
			push_error("[AnimCreator] KneeHandle node missing in scaffold")
			return
		_knee[leg] = kh
		_knee_rest_pos[leg] = kh.global_position
	for limb: StringName in LIMB_ORDER:
		var handle := get_node_or_null(String((LIMB_NODES[limb] as Dictionary)["handle"])) as Node3D
		if handle == null:
			push_error("[AnimCreator] %s handle node missing in scaffold" % String(limb))
			return
		_handles[limb] = handle
		var pole := Node3D.new()
		pole.name = "%sAutoPole" % String(limb)
		add_child(pole)
		_poles[limb] = pole
		var proxy := Node3D.new()
		proxy.name = "%sTargetProxy" % String(limb)
		add_child(proxy)
		proxy.global_position = handle.global_position
		_proxy[limb] = proxy
		_snapshot_rest(limb)
		# Bras + jambes : solveur custom analytique stateless (refs base).
		# Aucun modifier runtime — rien à construire par membre.
		_handle_rest_rot[limb] = handle.global_transform.basis.get_rotation_quaternion()
	_update_auto_poles()
	_apply_override_clear()
	_built = true
	_ensure_preview_player()
	# Stale-build detector (25/09 : proxies snappés sur handles au build — si
	# les globals n'étaient pas propagées, le solve part de travers).
	var max_gap := 0.0
	for limb in LIMB_ORDER:
		if _proxy.has(limb) and _handles.has(limb):
			max_gap = maxf(max_gap, (_proxy[limb] as Node3D).global_position.distance_to((_handles[limb] as Node3D).global_position))
	print("[AnimCreator r%d ready — arms+legs custom analytic, wrist %s ankle %s torso %s head %s base=%s (9 clickable handles, no poles to steer) proxy_gap=%.1fmm" % [SCRIPT_REV, "on" if wrist_copy else "off", "on" if ankle_copy else "off", "on" if torso_copy else "off", "on" if head_copy else "off", _base_name, max_gap * 1000.0])


## Preview player PERSISTANT (nœud scène — 26/09 : la sélection vit dans le
## dock Animation, fin de la saisie texte). Le tool monte les libs au build :
## "takes" = pack labo (lecture seule, gracieux si absent), "authored" = lib
## de travail vide (le keyframing la remplira + sauvera authored_pack.res).
## Unload = stop() + clear (équivalent au FREE d'avant : sans animation
## courante le player ne drive rien — jamais de stop() qui garde une pose
## fantôme, sonde 25/09 : err 12 mm ; assigned = "" est invalide en 4.7).
## État player = session-only (le build respecte la sélection sauvée telle
## quelle ; l'Unload revient aux writers).
var _take_player: AnimationPlayer
var _take_current := ""
## Intention explicite (un unload ne doit pas ressusciter via rebuild paresseux).
var _take_want := false
## État AUTHORED (B2) : clip de la lib "authored" adopté pour relecture
## (player drive, writers effacés — même règle unique que les takes).
var _authored_current := ""
var _authored_want := false
## Tenue de fin différée (callback animation_finished → _process suivant :
## play+pause+seek(length) fige la dernière frame, le player 4.7 retombant
## au repos en fin naturelle).
var _hold_end := false
## Lib de travail (vide jusqu'à l'étape keyframing).
const AUTHORED_LIB := &"authored"
## Garde de réentrance dock ↔ exports.
var _syncing := false
## Preview explicitement relâchée (Unload / captures) : le dock garde assigned
## (impossible à vider en 4.7) donc le sync doit IGNORER cette valeur jusqu'à
## nouvel intent (autre anim au dock, ou export retouché). Chaîne ASSIGNED
## COMPLÈTE ("takes/x" ou "authored/y" — les deux previews partagent le même
## player). Sans ça l'Unload est ré-adopté la frame suivante.
var _last_release := StringName()


## Retrouve le player persistant, cale sa racine sur l'Armature et monte les
## deux libs. Fallback runtime (vieille scène sans le nœud) : même convention
## racine que l'ancien TakePlayer.
func _ensure_preview_player() -> void:
	if _take_player == null:
		_take_player = get_node_or_null("PreviewPlayer") as AnimationPlayer
		if _take_player == null:
			var rig0 := get_node_or_null("RigRoot")
			var arm0 := rig0.find_child("Armature", true, false) if rig0 != null else null
			if arm0 == null:
				push_error("[AnimCreator] Armature missing for take player")
				return
			_take_player = AnimationPlayer.new()
			_take_player.name = "TakePlayer"
			_take_player.root_node = ".."
			arm0.add_child(_take_player)
			_connect_preview_signals()
			return
	var rig := get_node_or_null("RigRoot")
	var arm := rig.find_child("Armature", true, false) if rig != null else null
	if arm != null:
		var want_root: NodePath = _take_player.get_path_to(arm)
		if _take_player.root_node != want_root:
			_take_player.root_node = want_root
	if not _take_player.has_animation_library(&"takes"):
		var lib := load(TAKE_PACK) as AnimationLibrary
		if lib != null:
			_take_player.add_animation_library(&"takes", lib)
		else:
			push_warning("[AnimCreator] take pack missing (fresh clone?) — take preview unavailable")
	if not _take_player.has_animation_library(AUTHORED_LIB):
		# Fichier absent au 1er run = normal (silencieux, pas d'ERROR moteur).
		# Bypass du cache loader (sinon une réouverture dans le même process
		# éditeur resservirait la version pré-save — sondé B3).
		var loaded: AnimationLibrary
		if FileAccess.file_exists(AUTHORED_PACK):
			loaded = ResourceLoader.load(AUTHORED_PACK, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
		if loaded != null:
			# Dupliquée : le travail session ne doit jamais aliaser le fichier.
			_take_player.add_animation_library(AUTHORED_LIB, loaded.duplicate() as AnimationLibrary)
			print("[AnimCreator] authored pack loaded (%d clips)" % loaded.get_animation_list().size())
		else:
			_take_player.add_animation_library(AUTHORED_LIB, AnimationLibrary.new())
	_connect_preview_signals()


## Fin naturelle d'un clip authored non-loop : le player 4.7 retombe au
## repos (sondé B2 : fin == T-pose, pas de tenue). On fige la dernière frame
## via le pattern éprouvé (play+pause+seek, applique sans tenir current) +
## miroir playing retombé sans seek (garde _syncing).
func _connect_preview_signals() -> void:
	if _take_player != null and not _take_player.animation_finished.is_connected(_on_preview_finished):
		_take_player.animation_finished.connect(_on_preview_finished)


func _on_preview_finished(anim: StringName) -> void:
	if _authored_current.is_empty() or anim != StringName("authored/" + _authored_current):
		return
	# Le seek intra-callback serait écrasé par la fin du traitement player :
	# on diffère d'une frame (pattern _pending_base).
	_hold_end = true


func _take_lib() -> AnimationLibrary:
	if _take_player == null or not _take_player.has_animation_library(&"takes"):
		return null
	return _take_player.get_animation_library(&"takes")


## Dock → exports (pré-yield, chaque frame). État POSSEDÉ PAR LE TOOL
## (sondes 26/09 : en 4.7 pause() VIDE current_animation — le player ne peut
## pas être la source de vérité : pause/stop laissent le même état
## current="" + assigned gardé, mais pause = preview figée à garder tandis
## que stop = ? — indécidable côté player). Donc : adoption sur ASSIGNED
## (persiste à travers pause/stop), sortie explicite uniquement (Unload /
## Set-as-base / T-pose). Miroirs play/frame seulement quand current tenu
## (jamais de query sans current : "has no current animation").
## "authored/" adopté ici aussi (B2, relecture) : mutuellement exclusif avec
## les takes (adopter l'un relâche l'autre, take_name export conservé pour
## resélection). authored_clip suit la sélection dock (miroir, comme
## take_name) ; authored_time n'est JAMAIS miroir (temps de travail possédé
## par l'humain — le dock reste un visualiseur).
func _sync_preview_selection() -> void:
	if _take_player == null or _syncing:
		return
	var a: StringName = _take_player.assigned_animation
	if a != &"" and a == _last_release:
		# Re-play explicite du même clip après release (le dock garde
		# assigned, impossible à vider en 4.7 — le re-play garde le même
		# assigned). Notre code ne laisse jamais playing sans état possédé
		# (establish/hold finissent pausés, les setters clearent le release
		# d'abord) : playing ici = appui play humain → on adopte. Sinon
		# (pausé) c'est le dormant post-release → on ignore.
		if not _take_player.is_playing():
			return
		_last_release = &""
	var sel := StringName("")
	if String(a).begins_with("takes/"):
		sel = StringName(String(a).trim_prefix("takes/"))
	elif String(a).begins_with("authored/"):
		var clip := StringName(String(a).trim_prefix("authored/"))
		var alib := _authored_lib()
		if alib == null or not alib.has_animation(clip):
			return
		if String(clip) != _authored_current:
			_last_release = &""
			_syncing = true
			_take_current = ""
			_take_want = false
			_authored_current = String(clip)
			authored_clip = String(clip)
			_authored_want = true
			_apply_override_clear()
			_snap_rig_to_rest()
			_syncing = false
			_apply_authored_state()
		return
	if sel == &"":
		return
	var lib := _take_lib()
	if lib == null or not lib.has_animation(sel):
		return
	if String(sel) != _take_current and StringName("takes/" + String(sel)) != _last_release:
		_last_release = &""
		_syncing = true
		_authored_current = ""
		_authored_want = false
		_take_current = String(sel)
		take_name = String(sel)
		_take_want = true
		_apply_override_clear()
		_syncing = false
		# Établit l'affichage (play+pause+seek fige la 1re frame : sinon le
		# yield figerait une pose stale des writers).
		_apply_take_state()
	# Miroirs (current tenu uniquement).
	if not _take_current.is_empty() and _take_player.current_animation != &"":
		if take_playing != _take_player.is_playing():
			take_playing = _take_player.is_playing()
		var f: int = int(round(_take_player.get_current_animation_position() * 60.0))
		if take_frame != f:
			take_frame = f


## Exports → player (setters) : assigne + play/pause + seek exact si pausé
## (en lecture, la position avance seule — jamais de seek qui se battrait).
func _apply_take_state() -> void:
	if _take_player == null or _syncing or not is_node_ready():
		return
	if String(take_name).is_empty() or not _take_want:
		return
	var lib := _take_lib()
	if lib == null or not lib.has_animation(StringName(take_name)):
		push_error("[AnimCreator] take not in pack: %s" % take_name)
		return
	var target := StringName("takes/" + String(take_name))
	if _take_current != String(take_name):
		_take_current = String(take_name)
		# Clear : les overrides du repos (ou d'une ancienne base) pollueraient
		# la take affichée ET sa capture (live ≠ take pure).
		_apply_override_clear()
	var cur: StringName = _take_player.current_animation
	if cur != target:
		_take_player.play(target)
		_take_player.pause()
	if take_playing:
		if not _take_player.is_playing():
			_take_player.play(target)
	elif _take_player.is_playing():
		_take_player.pause()
	# Seek sur vérité live (pas le miroir take_playing : après un pause-dock
	# current est vidé et le miroir peut rester true — is_playing() ne ment
	# jamais et ne coûte aucune erreur).
	if not _take_player.is_playing():
		var want: float = float(maxi(take_frame, 0)) / 60.0
		if _take_player.current_animation == &"":
			# Figé sans current (post-pause) : play+pause+seek ré-établit la
			# pose gelée (applique sans tenir current). Le seek est OBLIGATOIRE
			# ici : play+pause synchrones n'évaluent jamais (aucune frame
			# entre les deux) — sans lui, rien n'est écrit (live = rest,
			# sondé B2.1). Exact à motion_scale constant (import partagé).
			_take_player.play(target)
			_take_player.pause()
			_take_player.seek(want, true)
		elif absf(_take_player.get_current_animation_position() - want) > 0.0005:
			_take_player.seek(want, true)


## Exports → player (sélection dock + authored_time) : assigne + fige +
## seek exact si pausé (en lecture, la position avance seule — jamais de seek
## qui se battrait ; authored_time écrit = seek si pausé, ignoré en lecture).
## Le TRANSPORT (play/stop/loop) vit au dock Animation.
func _apply_authored_state() -> void:
	if _take_player == null or _syncing or not is_node_ready():
		return
	var clip := String(authored_clip).strip_edges()
	if clip.is_empty() or not _authored_want:
		return
	var lib := _authored_lib()
	if lib == null or not lib.has_animation(StringName(clip)):
		push_error("[AnimCreator] authored clip missing: %s" % clip)
		return
	var target := StringName("authored/" + clip)
	if _authored_current != clip:
		_authored_current = clip
		# Clear : les overrides des writers pollueraient le clip affiché.
		_apply_override_clear()
		# Clips standard (D dans les os) : le rig doit être au repos en
		# lecture, sinon double descente (os + rig déplacé de session).
		_snap_rig_to_rest()
	var cur: StringName = _take_player.current_animation
	if cur != target:
		_take_player.play(target)
		_take_player.pause()
	if not _take_player.is_playing():
		var a: Animation = lib.get_animation(StringName(clip))
		var want: float = clampf(maxf(authored_time, 0.0), 0.0, a.length if a != null else 0.0)
		if _take_player.current_animation == &"":
			# Même pattern que les takes : le seek force l'évaluation
			# (play+pause synchrones n'écrivent rien) ; exact à motion_scale
			# constant (import partagé).
			_take_player.play(target)
			_take_player.pause()
			_take_player.seek(want, true)
		elif absf(_take_player.get_current_animation_position() - want) > 0.0005:
			_take_player.seek(want, true)


## Bouton Edit authored : fige le clip lu (pause) et bascule sa pose gelée
## en base de travail (même capture différée que Set-as-base : handles
## re-snappés, deltas zérovisés, pôles take-aware) — retoucher + Key pose
## pour corriger. L'ancienne base est remplacée (T-pose base la restaure).
func edit_authored() -> void:
	if _skeleton == null:
		push_warning("[AnimCreator] edit-authored: rig not built")
		return
	if _authored_current.is_empty():
		push_warning("[AnimCreator] edit-authored: nothing adopted — select an authored clip at the dock first")
		return
	var t := -1.0
	if _take_player != null and _take_player.current_animation != &"":
		t = _take_player.get_current_animation_position()
	if _take_player != null and _take_player.is_playing():
		_take_player.pause()
	_base_name = "authored:%s@%.3fs" % [_authored_current, t] if t >= 0.0 else "authored:%s" % _authored_current
	_pending_base = true
	print("[AnimCreator] editing authored next frame…")


## Bouton New clip : cible fraîche pose_NN (premier libre), temps à 0,
## preview authored relâchée (retour WRITERS), clip vide assuré.
func new_authored_clip() -> void:
	var lib := _authored_lib()
	if lib == null:
		push_warning("[AnimCreator] new-clip: rig not built")
		return
	var n := 1
	while lib.has_animation(StringName("pose_%02d" % n)):
		n += 1
	_release_preview()
	authored_clip = "pose_%02d" % n
	authored_time = 0.0
	_ensure_authored_anim()
	print("[AnimCreator] new clip %s" % String(authored_clip))


## Ramène le RigRoot à son repos (lectures AUTHORED : clips standard, D
## dans les os — tout écart session fausserait la pose d'une double
## descente). Le goal suit (glide slew au retour writers, sans pop).
func _snap_rig_to_rest() -> void:
	var rr := get_node_or_null("RigRoot") as Node3D
	if rr == null:
		return
	rr.global_position = _rig_rest
	if _hips != null:
		_hips_goal_off = _hips.global_position - rr.global_position


## Shift bassin en skeleton-space (convention Mixamo : Root fixe à
## l'origine, Hips porte le delta rig). SOURCE UNIQUE pour key_pose
## (session) et _write_dense_keys_at (bake) — les deux writers écrivent le
## même shift, les clips sont standard dans les deux cas.
func _authored_shift_sk() -> Vector3:
	var rr := get_node_or_null("RigRoot") as Node3D
	var rig_now: Vector3 = rr.global_position if rr != null else _rig_rest
	return _skeleton.global_transform.basis.inverse() * (rig_now - _rig_rest)


## Relâche la preview vers les writers (désélection dock, Unload, captures).
## take_name export conservé pour resélection. Couvre TAKE + AUTHORED (B2) :
## _last_release garde l'assigned COMPLET (le dock le conserve après stop).
func _release_preview() -> void:
	_take_want = false
	_take_current = ""
	_authored_want = false
	_authored_current = ""
	var a: StringName = _take_player.assigned_animation if _take_player != null else StringName("")
	_last_release = a
	# Le stop() restaure les propriétés NŒUD animées par les clips qui en
	# ont (legacy) : on sauve/restitue autour, sinon le ré-ancrage ci-dessous
	# cimente un off faux et le slew tient le rig au mauvais endroit.
	var _rr := get_node_or_null("RigRoot") as Node3D
	var _rigpos := (_rr as Node3D).position if _rr != null else Vector3.ZERO
	if _take_player != null:
		# stop() vide le current (assigned restant = dormant, ignoré par le
		# sync qui ne lit que current). assigned = "" est invalide en 4.7
		# (erreur "Animation not found", no-op).
		_take_player.stop()
	if _rr != null:
		_rr.position = _rigpos
	if _skeleton == null:
		return
	_apply_override_clear()
	_solve_pos.clear()
	_solve_fore.clear()
	_solve_end.clear()
	_solve_upper.clear()
	_solve_middle.clear()
	_spine_solved_pos.clear()
	_spine_solved_quat.clear()
	# Goal rig-follow ré-ancré sur le rig courant : retour writers en glide
	# slew, sans pop.
	if _hips != null and _rr != null:
		_hips_goal_off = _hips.global_position - _rr.global_position


## Décharge la take (take_name conservé pour resélection).
## Solveurs custom stateless : aucun rebuild nécessaire (l'err 21 mm fantôme
## TwoBone meurt avec la migration REV 23). Clear des snapshots pour éviter
## le pop d'1 frame sur writers stale.
func _unload_take() -> void:
	_release_preview()


## Preview chargée (TAKE ou AUTHORED, B2) = les writers + solveurs
## s'effacent (règle unique : rien ne touche la pose affichée).
func _take_driving() -> bool:
	return not _take_current.is_empty() or not _authored_current.is_empty()


## Playhead de la take (secondes) — seam pour le futur bake.
func take_time() -> float:
	if _take_player == null or _take_current.is_empty():
		return 0.0
	return _take_player.get_current_animation_position()


func take_length() -> float:
	if _take_player == null or _take_current.is_empty():
		return 0.0
	var a: Animation = _take_player.get_animation(StringName("takes/" + _take_current))
	return a.length if a != null else 0.0


## Lib authored de travail : chargée depuis authored_pack.res si présent
## (B3), sinon vide. Le keyframing la remplit (session, clips standard),
## Save la persiste TELLE QUELLE.
func _authored_lib() -> AnimationLibrary:
	if _take_player == null or not _take_player.has_animation_library(AUTHORED_LIB):
		return null
	return _take_player.get_animation_library(AUTHORED_LIB)


## Persistance authored (B3) : le pack vit à côté de la scène (contenu
## projet, versionné) ; le jeu le lira plus tard (promo slots — hors scope).
const AUTHORED_PACK := "res://scenes/anim_creator/authored_pack.res"

## Bouton Save authored : persiste la lib "authored" TELLE QUELLE (clips
## standard : os seuls, comme les takes — exportable, capsule-safe).
## length/step/loop conservés. Zéro clip = pack vide valide.
func save_authored() -> void:
	var lib := _authored_lib()
	if lib == null:
		push_warning("[AnimCreator] save-authored: rig not built")
		return
	var out := AnimationLibrary.new()
	var nclip := 0
	for clip in lib.get_animation_list():
		var cp: Animation = (lib.get_animation(clip) as Animation).duplicate()
		out.add_animation(clip, cp)
		nclip += 1
	var err := ResourceSaver.save(out, AUTHORED_PACK)
	if err != OK:
		push_error("[AnimCreator] save-authored FAILED: %s" % error_string(err))
		return
	print("[AnimCreator] saved %d clips → %s" % [nclip, AUTHORED_PACK])


## Bake Transition (minimal) : rebake tout le clip authored à 30 FPS
## en ré-échantillonnant l'IK complet — overwrite le clip courant.
## Un seul bouton, 30 FPS, tout inclus (hips, pieds, mains, colonne, pôles).
const BAKE_FPS := 30
## Pin statique inter-ancres (REV 39) : sous ce seuil de mouvement entre deux
## ancres, ce n'est pas une intention mais de la variance de solve (ex. pied
## +24 mm entre T-pose et crouch, handles jamais touchés) → figé à la moyenne.
## Un vrai mouvement (pas, geste main) fait >> seuil et passe intact.
const BAKE_PIN_DIST := 0.03
const BAKE_PIN_ANGLE := 0.05

## FK forward reconstruction: read bone local transforms from Animation at time,
## then parent -> child to get world poses. Pure data, zero player.
func _reconstruct_global_poses_at(anim: Animation, time: float) -> Dictionary:
	var skb: Basis = _skeleton.global_transform.basis
	var bone_count: int = _skeleton.get_bone_count()

	# Build track index map: "GeneralSkeleton:BoneName:TYPE" -> track_idx
	var track_map: Dictionary = {}
	for ti in anim.get_track_count():
		var path: NodePath = anim.track_get_path(ti)
		var ttype: int = anim.track_get_type(ti)
		track_map[String(path) + ":" + str(ttype)] = ti

	# Read local transforms (skeleton space) at time. Les positions cléées
	# sont DÉSCALÉES (/ motion_scale, cf. key_pose REV 30 : live == raw × ms)
	# → on re-multiplie ici pour retrouver les vrais locaux (REV 39 : sans
	# ça les cibles du bake sont ~5 % exagérées). Rotations intactes.
	var ms: float = _skeleton.motion_scale
	if absf(ms) < 0.001:
		ms = 1.0
	var local_poses: Dictionary = {}
	for i in bone_count:
		var bn: StringName = _skeleton.get_bone_name(i)
		var pk: String = "GeneralSkeleton:" + String(bn) + ":" + str(Animation.TYPE_POSITION_3D)
		var rk: String = "GeneralSkeleton:" + String(bn) + ":" + str(Animation.TYPE_ROTATION_3D)

		var pos: Vector3 = Vector3.ZERO
		var rot: Quaternion = Quaternion.IDENTITY

		if track_map.has(pk):
			var tpi: int = track_map[pk]
			var ki: int = anim.track_find_key(tpi, time, Animation.FIND_MODE_EXACT)
			if ki != -1:
				pos = anim.track_get_key_value(tpi, ki) as Vector3
			else:
				# No exact key — interpolate (linear for pos)
				ki = anim.track_find_key(tpi, time, Animation.FIND_MODE_NEAREST)
				if ki != -1:
					pos = anim.track_get_key_value(tpi, ki) as Vector3

		if track_map.has(rk):
			var tri: int = track_map[rk]
			var ki: int = anim.track_find_key(tri, time, Animation.FIND_MODE_EXACT)
			if ki != -1:
				rot = anim.track_get_key_value(tri, ki) as Quaternion
			else:
				ki = anim.track_find_key(tri, time, Animation.FIND_MODE_NEAREST)
				if ki != -1:
					rot = anim.track_get_key_value(tri, ki) as Quaternion

		local_poses[bn] = Transform3D(Basis(rot), pos * ms)

	# FK forward: parent -> child using pre-computed hierarchy order
	var order: Array[int] = _get_bone_hierarchy_order()
	var global_poses: Dictionary = {}
	for i in order:
		var bn: StringName = _skeleton.get_bone_name(i)
		var local: Transform3D = local_poses[bn]
		var p: int = _skeleton.get_bone_parent(i)
		if p != -1:
			var parent_bn: StringName = _skeleton.get_bone_name(p)
			var parent_global: Transform3D = global_poses[parent_bn]
			global_poses[bn] = parent_global * local
		else:
			global_poses[bn] = local

	return global_poses

## Returns bone indices in parent-first order (roots first, then children).
func _get_bone_hierarchy_order() -> Array[int]:
	var bone_count: int = _skeleton.get_bone_count()
	var order: Array[int] = []
	var visited: Array[bool] = []
	visited.resize(bone_count)
	for i in bone_count:
		visited[i] = false
	# DFS from roots
	for i in bone_count:
		if _skeleton.get_bone_parent(i) == -1:
			_dfs_collect_order(i, order, visited)
	# Any remaining (disconnected) bones
	for i in bone_count:
		if not visited[i]:
			_dfs_collect_order(i, order, visited)
	return order

func _dfs_collect_order(idx: int, order: Array[int], visited: Array[bool]) -> void:
	if visited[idx]:
		return
	visited[idx] = true
	order.append(idx)
	# Add children
	for i in _skeleton.get_bone_count():
		if _skeleton.get_bone_parent(i) == idx:
			_dfs_collect_order(i, order, visited)


## Locales os squelette complet à une ancre (REV 41 — canal orientations du
## bake) : FK globals reconstruites (exactes aux ancres : key_pose écrit tous
## les os à chaque clé) → locales parent-relatives. Seules les rotations sont
## consommées (les positions viennent de l'IK résolu) ; le /ms des positions
## est déjà résorbé dans la reconstruction.
func _capture_anchor_locals(anim: Animation, time: float) -> Dictionary:
	var globals: Dictionary = _reconstruct_global_poses_at(anim, time)
	var order: Array[int] = _get_bone_hierarchy_order()
	var locals: Dictionary = {}
	for i in order:
		var bn: StringName = _skeleton.get_bone_name(i)
		if not globals.has(bn):
			continue
		var g: Transform3D = globals[bn]
		var p: int = _skeleton.get_bone_parent(i)
		if p != -1:
			var parent_bn: StringName = _skeleton.get_bone_name(p)
			if not globals.has(parent_bn):
				continue
			var pg: Transform3D = globals[parent_bn]
			var l: Transform3D = pg.affine_inverse() * g
			locals[bn] = { &"rot": l.basis.get_rotation_quaternion() }
		else:
			locals[bn] = { &"rot": g.basis.get_rotation_quaternion() }
	return locals

func bake_transition_all() -> void:
	if _skeleton == null:
		push_warning("[AnimCreator] bake-all: rig not built")
		return
	var lib := _authored_lib()
	if lib == null:
		push_warning("[AnimCreator] bake-all: no authored lib")
		return
	var clip_name := String(authored_clip).strip_edges()
	if clip_name.is_empty() or not lib.has_animation(clip_name):
		push_warning("[AnimCreator] bake-all: clip '%s' not found" % clip_name)
		return
	var anim: Animation = lib.get_animation(clip_name)
	if anim.length <= 0.0:
		push_warning("[AnimCreator] bake-all: clip length zero")
		return

	# Preserve authored adoption state across bake (so clip stays adopted,
	# avoiding re-adoption + forced pause when user presses play in dock)
	var was_authored_current: String = _authored_current
	var was_authored_want: bool = _authored_want

	# 1) Collecter tous les temps d'ancrage (clés existantes sur n'importe quel track)
	var anchors: Array[float] = _collect_anchor_times(anim)
	if anchors.size() < 2:
		push_warning("[AnimCreator] bake-all: need at least 2 anchor keys")
		return

	# 2) Sauvegarder l'état actuel des handles/proxies pour restauration
	var saved_handles: Dictionary = _capture_handles_state()
	var saved_proxies: Dictionary = _capture_proxies_state()

	# 3) Relâcher toute preview active MAIS garde l'adoption authored
	_take_want = false
	_take_current = ""
	# Ne PAS toucher à _authored_current / _authored_want ici
	var a: StringName = _take_player.assigned_animation if _take_player != null else StringName("")
	_last_release = a
	var _rr := get_node_or_null("RigRoot") as Node3D
	var _rigpos := (_rr as Node3D).position if _rr != null else Vector3.ZERO
	if _take_player != null:
		_take_player.stop()
	if _rr != null:
		_rr.position = _rigpos
	if _skeleton == null:
		return
	_apply_override_clear()
	_solve_pos.clear()
	_solve_fore.clear()
	_solve_end.clear()
	_solve_upper.clear()
	_solve_middle.clear()
	_spine_solved_pos.clear()
	_spine_solved_quat.clear()
	if _hips != null and _rr != null:
		_hips_goal_off = _hips.global_position - _rr.global_position

	# 3b) Le rig SUIT le handle pendant le bake (comme en session
	# interactive, REV 38) : l'IK voit le même monde que key_pose, et le
	# shift rig→Hips écrit ensuite est réel. Position pré-bake sauvée pour
	# restauration de l'état éditeur après boucle.
	var saved_rig_pos := Vector3.ZERO
	var _rr_bake := get_node_or_null("RigRoot") as Node3D
	if _rr_bake != null:
		saved_rig_pos = _rr_bake.global_position

	# 4) Pour chaque segment [ti, ti+1], échantillonner et re-baker
	var step: float = 1.0 / BAKE_FPS
	var total_written: int = 0

	for seg in range(anchors.size() - 1):
		var t0: float = anchors[seg]
		var t1: float = anchors[seg + 1]
		if t1 <= t0:
			continue

		# Capturer les poses handles aux deux bornes (+ locales os squelette
		# complet pour le canal orientations, REV 41)
		var pose_a: Dictionary = _capture_handle_poses_at(t0, anim)
		var pose_b: Dictionary = _capture_handle_poses_at(t1, anim)
		var rots_a: Dictionary = _capture_anchor_locals(anim, t0)
		var rots_b: Dictionary = _capture_anchor_locals(anim, t1)

		# Pin statique (REV 39) : un handle quasi-immobile entre deux ancres
		# est figé à la moyenne — pieds plantés, zéro jitter.
		_pin_static_handles(pose_a, pose_b)

		# Échantillonner le segment (exclure t1 pour éviter doublon, sauf dernier segment)
		var t: float = t0
		var is_last_segment: bool = (seg == anchors.size() - 2)
		while t < t1 - 0.0001 or (is_last_segment and abs(t - t1) < 0.0001):
			# Interpoler handles
			var alpha: float = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
			var interp_handles: Dictionary = _interpolate_handles(pose_a, pose_b, alpha)

			# Appliquer handles (POSITIONS seules, cubes au repos) + résoudre
			# IK complet, rig-follow ACTIF. Les orientations sont reprises par
			# slerp d'ancres à l'écriture (REV 41) : aucun double-framing des
			# writers relatifs (poignet/cheville/dos/bassin).
			_apply_handles_and_solve(interp_handles, false, true)

			# Écrire clés denses pour tous les os à ce temps (positions =
			# IK résolu, orientations = slerp des locales d'ancre).
			_write_dense_keys_at(anim, t, rots_a, rots_b, alpha)
			total_written += 1

			t += step
			# Clamp final pour le dernier point exact
			if is_last_segment and t > t1 - 0.0001 and t < t1 + 0.0001:
				t = t1

	# 5) Restaurer handles/proxies + rig pré-bake (l'état éditeur est
	# inchangé ; le clip reste standard : shift dans Hips, rig fixe en
	# lecture).
	_restore_handles_state(saved_handles)
	_restore_proxies_state(saved_proxies)
	if _rr_bake != null:
		_rr_bake.global_position = saved_rig_pos
		if _hips != null:
			_hips_goal_off = _hips.global_position - _rr_bake.global_position

	# 6) Re-capturer la base (writers reprennent la main)
	_capture_rest_base()
	_derive_base_refs()

	# 7) Restaurer l'état d'adoption authored (le clip reste adopté)
	_authored_current = was_authored_current
	_authored_want = was_authored_want

	# 8) Reset player position to 0 for authored clip so Play starts from beginning
	# (player was left at end after previous playback; bake doesn't move it)
	if _take_player != null and not was_authored_current.is_empty():
		var target := StringName("authored/" + was_authored_current)
		if _take_player.current_animation == target or _take_player.assigned_animation == target:
			_take_player.seek(0.0, true)
			print("[AnimCreator DBG] bake-all: reset player to 0.0 for %s" % target)

	# Debug: verify baked animation
	var track0_keys := anim.track_get_key_count(0)
	var track1_keys := anim.track_get_key_count(1)
	print("[AnimCreator DBG] bake-all verify: clip=%s, length=%.3f, track0_keys=%d, track1_keys=%d, total_written=%d" % [clip_name, anim.length, track0_keys, track1_keys, total_written])
	# Check first and last key times on track 0
	if track0_keys > 0:
		var first_t := anim.track_get_key_time(0, 0)
		var last_t := anim.track_get_key_time(0, track0_keys - 1)
		print("[AnimCreator DBG] bake-all: first key at %.3f, last key at %.3f" % [first_t, last_t])
	# Contrôle REV 38 : la track Hips doit porter la descente (pas une ligne plate)
	for ti in anim.get_track_count():
		if String(anim.track_get_path(ti)) == "GeneralSkeleton:Hips" and anim.track_get_type(ti) == Animation.TYPE_POSITION_3D:
			var y0 := -999.0
			var ymid := -999.0
			for k in anim.track_get_key_count(ti):
				var kt: float = anim.track_get_key_time(ti, k)
				var kv: Vector3 = anim.track_get_key_value(ti, k)
				if absf(kt - anchors[0]) < 0.0005:
					y0 = kv.y
				if anchors.size() > 1 and absf(kt - anchors[1]) < 0.0005:
					ymid = kv.y
			print("[AnimCreator DBG] bake-all: Hips pos.y @ t=%.3f → %.4f, @ t=%.3f → %.4f (drop=%.3f)" % [anchors[0], y0, anchors[1] if anchors.size() > 1 else -1.0, ymid, y0 - ymid])
			break

	print("[AnimCreator] bake-all: %s — %d keys written @ %d FPS (%d segments)" % [clip_name, total_written, BAKE_FPS, anchors.size() - 1])


## Collecte tous les temps uniques où il y a au moins une clé (tous tracks)
func _collect_anchor_times(anim: Animation) -> Array[float]:
	var times_set: Dictionary = {}
	for ti in anim.get_track_count():
		var n: int = anim.track_get_key_count(ti)
		for k in n:
			var kt: float = anim.track_get_key_time(ti, k)
			if kt >= 0.0 and kt <= anim.length:
				times_set[kt] = true
	var anchors: Array[float] = []
	for k in times_set:
		anchors.append(k)
	anchors.sort()
	# S'assurer que 0.0 et length sont présents
	if not anchors.has(0.0):
		anchors.insert(0, 0.0)
	if not anchors.has(anim.length):
		anchors.append(anim.length)
	return anchors


## Capture l'état complet des handles (position + rotation) à un temps donné
## en lisant les clés du clip (Animation object) + FK forward → poses globales.
## Zéro player, zéro instanciation, déterministe.
func _capture_handle_poses_at(time: float, anim: Animation) -> Dictionary:
	var pose: Dictionary = {}

	# Reconstruire poses globales depuis les clés de l'anim (FK forward)
	var global_poses: Dictionary = _reconstruct_global_poses_at(anim, time)

	# Map handle_name -> bone_name
	var handle_bones: Dictionary = {
		&"Hips": &"Hips",
		&"LeftFoot": &"LeftFoot",
		&"RightFoot": &"RightFoot",
		&"LeftHand": &"LeftHand",
		&"RightHand": &"RightHand",
		&"Torso": &"UpperChest",
		&"Head": &"Head",
	}
	for h_name in handle_bones:
		var bn: StringName = handle_bones[h_name]
		if global_poses.has(bn):
			var g: Transform3D = global_poses[bn]
			pose[h_name] = {
				&"pos": g.origin,
				&"rot": g.basis.get_rotation_quaternion()
			}

	# DEBUG: afficher poses capturées
	var hips_y: float = global_poses[&"Hips"].origin.y if global_poses.has(&"Hips") else 0.0
	print("[BAKE DEBUG] capture at t=%.3f: Hips bone global pos=%.3f, anim len=%.3f" % [time, hips_y, anim.length])
	for h_name in handle_bones:
		if pose.has(h_name):
			print("[BAKE DEBUG]   handle %s pos=%.3f" % [h_name, pose[h_name][&"pos"].y])

	# Pôles auto : calculer depuis les poses os reconstruites (même logique que _update_auto_poles)
	var skb: Basis = _skeleton.global_transform.basis
	for limb in LIMB_ORDER:
		if not LEG_BONES.has(limb):
			continue
		if not _poles.has(limb) or not _joint_rest.has(limb) or not _upper_rest.has(limb):
			continue
		var bones: Dictionary = _bones_of(limb)
		# Root = upper bone global pos (cuisse) — threadé par bassin comme en runtime
		var root_w: Vector3
		if global_poses.has(bones["upper"]):
			root_w = global_poses[bones["upper"]].origin
		else:
			root_w = _skeleton.to_global(_upper_rest[limb] as Vector3)
		# Target = handle pied (si capturé) sinon end bone
		var handle_name: StringName = &"LeftFoot" if String(limb).begins_with("Left") else &"RightFoot"
		var target_w: Vector3
		if pose.has(handle_name):
			target_w = pose[handle_name][&"pos"]
		elif global_poses.has(bones["end"]):
			target_w = global_poses[bones["end"]].origin
		else:
			target_w = _skeleton.to_global(_rest[limb] as Vector3)
		var line: Vector3 = target_w - root_w
		if line.length() < 0.05:
			continue
		var along: Vector3 = line.normalized()
		# Direction anatomique (même que _update_auto_poles)
		var fwd := ARM_POLE_DIR
		if _pole_dir_cap.has(limb):
			fwd = (skb * (_pole_dir_cap[limb] as Vector3)).normalized()
		elif LEG_BONES.has(limb):
			var side_sign := 1.0 if String(limb).begins_with("Left") else -1.0
			fwd = Vector3(side_sign * LEG_POLE_LAT, 0.0, 1.0).normalized()
		var perp: Vector3 = fwd - along * fwd.dot(along)
		if perp.length() < 0.05:
			continue
		var dir: Vector3 = perp.normalized()
		var pole_pos: Vector3 = _skeleton.to_global(_joint_rest[limb] as Vector3) + dir * POLE_DIST
		# Knee offset (si knee_copy actif)
		if knee_copy and _knee.has(limb):
			var knee_handle: Node3D = _knee[limb]
			var knee_rest: Vector3 = _knee_rest_pos.get(limb, knee_handle.global_position)
			var off: Vector3 = knee_handle.global_position - knee_rest
			if off.length() > KNEE_OFF_MAX:
				off = off.normalized() * KNEE_OFF_MAX
			pole_pos += off
		pose[&"pole_" + String(limb)] = { &"pos": pole_pos }

	# Genoux handles : position = joint (middle bone) depuis poses reconstruites
	for limb in LIMB_ORDER:
		if not LEG_BONES.has(limb):
			continue
		var bones: Dictionary = _bones_of(limb)
		if global_poses.has(bones["middle"]):
			var knee_pos: Vector3 = global_poses[bones["middle"]].origin
			var h_name: StringName = &"LeftKnee" if String(limb).begins_with("Left") else &"RightKnee"
			pose[h_name] = {
				&"pos": knee_pos,
				&"rot": Quaternion()
			}

	return pose


## Pin statique inter-ancres (REV 39) : si un handle bouge moins que
## BAKE_PIN_DIST / BAKE_PIN_ANGLE entre deux ancres, ce n'est pas une
## intention mais de la variance de solve (ex. pied +24 mm entre T-pose et
## crouch, handles jamais touchés) — on fige les deux bornes à leur moyenne
## (lerp positions, slerp rotations). Les mouvements voulus (>> seuil)
## passent intacts. On mute les captures (pas le clip) : aux ancres partagées
## chaque segment écrit une valeur unique, continuité garantie, aucun pop.
func _pin_static_handles(pose_a: Dictionary, pose_b: Dictionary) -> void:
	for key in pose_a:
		if not pose_b.has(key):
			continue
		var a: Dictionary = pose_a[key]
		var b: Dictionary = pose_b[key]
		if not (a.has(&"pos") and b.has(&"pos")):
			continue
		var pa: Vector3 = a[&"pos"]
		var pb: Vector3 = b[&"pos"]
		if pa.distance_to(pb) < BAKE_PIN_DIST:
			var mid: Vector3 = pa.lerp(pb, 0.5)
			a[&"pos"] = mid
			b[&"pos"] = mid
		if a.has(&"rot") and b.has(&"rot"):
			var qa: Quaternion = a[&"rot"]
			var qb: Quaternion = b[&"rot"]
			if qa.angle_to(qb) < BAKE_PIN_ANGLE:
				var qm: Quaternion = qa.slerp(qb, 0.5)
				a[&"rot"] = qm
				b[&"rot"] = qm


## Interpole deux poses de handles (alpha 0..1)
func _interpolate_handles(pose_a: Dictionary, pose_b: Dictionary, alpha: float) -> Dictionary:
	var out: Dictionary = {}
	for key in pose_a:
		if not pose_b.has(key):
			continue
		var a: Dictionary = pose_a[key]
		var b: Dictionary = pose_b[key]
		if a.has(&"pos") and b.has(&"pos"):
			var interp: Dictionary = { &"pos": a[&"pos"].lerp(b[&"pos"], alpha) }
			# Rotation seulement si les deux l'ont (pôles = pos seulement)
			if a.has(&"rot") and b.has(&"rot"):
				interp[&"rot"] = a[&"rot"].slerp(b[&"rot"], alpha)
			out[key] = interp
		else:
			out[key] = a.duplicate()
	return out


## Applique handles interpolés aux nodes réels + lance solveurs complets
## [param skip_rig_follow] si true, ne bouge pas RigRoot (session live : le
## _process gère le follow lui-même avec slew).
## [param keep_rest_rot] si true (bake REV 41), seules les POSITIONS sont
## posées — les cubes gardent leur orientation repos : les writers relatifs
## sortent leur base (déterministe, pas de double-framing), les orientations
## finales viennent du slerp d'ancres à l'écriture.
func _apply_handles_and_solve(handles: Dictionary, skip_rig_follow: bool = false, keep_rest_rot: bool = false) -> void:
	# Appliquer positions handles visibles (mapping REV 40 : les
	# noms logiques de capture — LeftHand, LeftFoot... — ne sont PAS les clés
	# de _handles, cléé par membre Left/Right/LeftLeg/RightLeg).
	for key in handles:
		var data: Dictionary = handles[key]
		if not data.has(&"pos"):
			continue

		# Pôles auto
		if String(key).begins_with("pole_") and _poles.has(String(key).replace("pole_", "")):
			var limb := String(key).replace("pole_", "")
			(_poles[limb] as Node3D).global_position = data[&"pos"]
			continue

		# Handles nommés (Hips, pieds, mains, genoux, torse, tête)
		var n := _handle_node(StringName(String(key)))
		if n != null:
			n.global_position = data[&"pos"]
			if not keep_rest_rot and data.has(&"rot"):
				n.global_transform.basis = Basis(data[&"rot"])

	# Mettre à jour proxies (slew targets) pour correspondre aux handles
	# Copie directe sans slew pour le bake (instantané)
	for limb in _proxy:
		if _handles.has(limb):
			var h: Node3D = _handles[limb]
			var px: Node3D = _proxy[limb]
			px.global_position = h.global_position
			px.global_transform.basis = h.global_transform.basis

	# Résoudre dans l'ordre exact du _process : hips -> spine -> auto-poles -> limbs
	_solve_hips()
	_apply_spine()
	_update_auto_poles()

	# RigRoot suit Hips (comme dans _process) — skip pendant bake (rig fixe convention Mixamo)
	if not skip_rig_follow and _hips != null:
		var rig := get_node_or_null("RigRoot") as Node3D
		if rig != null:
			var goal: Vector3 = _hips.global_position - _hips_goal_off
			rig.global_position = goal

	# Solveurs membres
	for limb in LIMB_ORDER:
		if LEG_BONES.has(limb):
			_solve_leg(limb)
		else:
			_solve_arm(limb)

	# Writers poignet/cheville (même frame)
	_apply_stored_wrist()
	_apply_stored_ankle()


## Écrit clés denses (position + rotation locale) pour TOUS les os à ce temps.
## Canaux séparés (REV 41) : positions = IK résolu (+ shift Hips + /ms, même
## logique que key_pose) ; orientations = slerp des locales d'ancre (exact
## aux ancres, smooth entre — jamais de re-solve relatif qui appliquerait
## deux fois les repos poignet/cheville/dos/bassin).
## Pas de tenue auto : le bake échantillonne explicitement t=length.
func _write_dense_keys_at(anim: Animation, time: float, rot_a: Dictionary, rot_b: Dictionary, alpha: float) -> void:
	var idx_of := {}
	for ti in anim.get_track_count():
		idx_of[String(anim.track_get_path(ti)) + ":" + str(anim.track_get_type(ti))] = ti

	var ms: float = _skeleton.motion_scale
	if absf(ms) < 0.001:
		ms = 1.0

	for i in _skeleton.get_bone_count():
		var bn := String(_skeleton.get_bone_name(i))
		var g: Transform3D = _skeleton.get_bone_global_pose(i)
		var p := _skeleton.get_bone_parent(i)
		var pg := Transform3D.IDENTITY
		if p != -1:
			pg = _skeleton.get_bone_global_pose(p)
		var local: Transform3D = pg.affine_inverse() * g

		# Convention Mixamo (REV 38) : Root fixe, Hips porte le delta rig —
		# MÊME source que key_pose (_authored_shift_sk). Pendant le bake le
		# rig SUIT le handle (comme en session), donc le shift est réel.
		var shift := Vector3.ZERO
		if bn == &"Hips":
			shift = _authored_shift_sk()

		local.origin = local.origin / ms + pg.basis.inverse() * shift

		var pk := "GeneralSkeleton:" + bn + ":" + str(Animation.TYPE_POSITION_3D)
		var rk := "GeneralSkeleton:" + bn + ":" + str(Animation.TYPE_ROTATION_3D)

		if idx_of.has(pk):
			var ti: int = idx_of[pk]
			var ki: int = anim.track_find_key(ti, time, Animation.FIND_MODE_EXACT)
			if ki != -1:
				anim.track_set_key_value(ti, ki, local.origin)
			else:
				anim.position_track_insert_key(ti, time, local.origin)

		if idx_of.has(rk):
			var ri: int = idx_of[rk]
			var rj: int = anim.track_find_key(ri, time, Animation.FIND_MODE_EXACT)
			var rq: Quaternion = local.basis.get_rotation_quaternion()
			var bns := StringName(bn)
			if rot_a.has(bns) and rot_b.has(bns):
				rq = (rot_a[bns][&"rot"] as Quaternion).slerp(rot_b[bns][&"rot"] as Quaternion, alpha)
			if rj != -1:
				anim.track_set_key_value(ri, rj, rq)
			else:
				anim.rotation_track_insert_key(ri, time, rq)


## Nœud réel pour chaque nom logique de handle (REV 40 — source unique).
## _handles est cléé par membre (Left/Right/LeftLeg/RightLeg), _torso/_head/
## _knee/_hips vivent à part : sans ce mapping, les écritures par noms de
## capture (LeftHand, LeftFoot...) tombent dans le vide — les nœuds ne
## bougent jamais et les proxies restent au repos (bras bakés en T-pose).
func _handle_node(logical: StringName) -> Node3D:
	match logical:
		&"Hips":
			return _hips
		&"LeftHand":
			return _handles.get(&"Left") as Node3D
		&"RightHand":
			return _handles.get(&"Right") as Node3D
		&"LeftFoot":
			return _handles.get(&"LeftLeg") as Node3D
		&"RightFoot":
			return _handles.get(&"RightLeg") as Node3D
		&"LeftKnee":
			return _knee.get(&"LeftLeg") as Node3D
		&"RightKnee":
			return _knee.get(&"RightLeg") as Node3D
		&"Torso":
			return _torso
		&"Head":
			return _head
	return null


## Sauvegarde l'état des handles visibles (cléé par noms logiques, via
## _handle_node — usage bake-only : _capture/_restore vont ensemble).
func _capture_handles_state() -> Dictionary:
	var state: Dictionary = {}
	var logicals := [&"Hips", &"LeftFoot", &"RightFoot",
		&"LeftHand", &"RightHand",
		&"LeftKnee", &"RightKnee",
		&"Torso", &"Head"]
	for logi in logicals:
		var h := _handle_node(logi)
		if h != null:
			state[logi] = { &"pos": h.global_position, &"rot": h.global_transform.basis.get_rotation_quaternion() }
	# Pôles
	for limb in _poles:
		var p: Node3D = _poles[limb]
		if p != null:
			state["pole_" + String(limb)] = { &"pos": p.global_position }
	return state


## Sauvegarde l'état des proxies
func _capture_proxies_state() -> Dictionary:
	var state: Dictionary = {}
	for limb in _proxy:
		var px: Node3D = _proxy[limb]
		if px != null:
			state[limb] = { &"pos": px.global_position, &"rot": px.global_transform.basis.get_rotation_quaternion() }
	return state


## Restaure l'état des handles (noms logiques via _handle_node, REV 40).
func _restore_handles_state(state: Dictionary) -> void:
	for key in state:
		var data: Dictionary = state[key]
		var key_str: String = String(key)
		if key_str.begins_with("pole_") and _poles.has(key_str.replace("pole_", "")):
			var limb: StringName = StringName(key_str.replace("pole_", ""))
			(_poles[limb] as Node3D).global_position = data[&"pos"]
			continue
		var h := _handle_node(StringName(key_str))
		if h != null:
			h.global_position = data[&"pos"]
			if data.has(&"rot"):
				h.global_transform.basis = Basis(data[&"rot"])


## Restaure l'état des proxies
func _restore_proxies_state(state: Dictionary) -> void:
	for limb in state:
		if _proxy.has(limb):
			var px: Node3D = _proxy[limb]
			px.global_position = state[limb][&"pos"]
			px.global_transform.basis = Basis(state[limb][&"rot"])


## Retourne le clip authored (créé si absent : longueur authored_length,
## step 1/60, loop NONE, 2 tracks par os pos+rot chemins GeneralSkeleton:Os —
## STANDARD, comme les takes : aucune track de nœud, exportable tel quel).
func _ensure_authored_anim() -> Animation:
	var lib := _authored_lib()
	if lib == null or _skeleton == null:
		return null
	var clip := String(authored_clip).strip_edges()
	if clip.is_empty():
		push_error("[AnimCreator] key-pose: authored_clip empty")
		return null
	var a: Animation
	if lib.has_animation(clip):
		a = lib.get_animation(clip)
	else:
		a = Animation.new()
		a.length = maxf(authored_length, 0.1)
		a.step = 1.0 / 60.0
		a.loop_mode = Animation.LOOP_NONE
		for i in _skeleton.get_bone_count():
			var path := NodePath("GeneralSkeleton:" + String(_skeleton.get_bone_name(i)))
			var pt := a.add_track(Animation.TYPE_POSITION_3D)
			a.track_set_path(pt, path)
			var rt := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(rt, path)
		lib.add_animation(clip, a)
	return a


## Bouton Key pose : clé la pose visible (global live → local parent-1 ×
## global, os, delta rig baké — régime takes-style) à authored_time dans
## authored_clip (créé si absent). La longueur s'étend si authored_time dépasse. Re-clé au
## même temps = valeur remplacée (find exact + set, jamais de doublon). En
## AUTHORED (B2), le visible = la pose du clip lu (re-clé identique = no-op ;
## pour corriger : Edit authored puis re-clé depuis les writers).
func key_pose() -> void:
	if _skeleton == null:
		push_warning("[AnimCreator] key-pose: rig not built")
		return
	var a := _ensure_authored_anim()
	if a == null:
		return
	var t := maxf(authored_time, 0.0)
	if t > a.length:
		a.length = t
	var idx_of := {}
	for ti in a.get_track_count():
		idx_of[String(a.track_get_path(ti)) + ":" + str(a.track_get_type(ti))] = ti
	var keyed := 0
	# Régime takes-style (27/09) : la translation du bassin vit dans le rig
	# en session (REV 20, pieds plantés) mais les clips sont STANDARD — le
	# delta rig est baké dans les positions d'os (référence = rig au repos) :
	# Convention Mixamo : Root fixe à l'origine, Hips descend (os Hips porte
	# le shift), pieds plantés, rig fixe. Rotations intactes.
	# Exportable tel quel (Blender/autre), capsule-safe côté jeu.
	var off_sk := _authored_shift_sk()
	# Clips en MÈTRES vrais (standard Blender) : le mixer multiplie les
	# translations évaluées par motion_scale (sondé : live == raw × ms), donc
	# le local lu (déjà scalé) est déscalé avant écriture — sinon 5% d'erreur.
	var ms: float = _skeleton.motion_scale
	if absf(ms) < 0.001:
		ms = 1.0
	for i in _skeleton.get_bone_count():
		var bn := String(_skeleton.get_bone_name(i))
		var g: Transform3D = _skeleton.get_bone_global_pose(i)
		var p := _skeleton.get_bone_parent(i)
		var pg := Transform3D.IDENTITY
		if p != -1:
			pg = _skeleton.get_bone_global_pose(p)
		var local: Transform3D = pg.affine_inverse() * g
		# Convention Mixamo : Root reste à l'origine (0,0,0), le Hips descend
		# vers lui — le shift ne s'applique QU'au Hips (os nommé "Hips"),
		# JAMAIS au Root ni aux autres racines. Les locaux enfants sont
		# parents-relatifs (indépendants du frame rig) — le shifter le Hips
		# suffit car il est le parent de toute la hiérarchie corps.
		var shift := Vector3.ZERO
		if bn == "Hips":
			shift = off_sk
		local.origin = local.origin / ms + pg.basis.inverse() * shift
		var pk := "GeneralSkeleton:" + bn + ":" + str(Animation.TYPE_POSITION_3D)
		var rk := "GeneralSkeleton:" + bn + ":" + str(Animation.TYPE_ROTATION_3D)
		if idx_of.has(pk):
			var ti: int = idx_of[pk]
			var ki: int = a.track_find_key(ti, t, Animation.FIND_MODE_EXACT)
			if ki != -1:
				a.track_set_key_value(ti, ki, local.origin)
			else:
				a.position_track_insert_key(ti, t, local.origin)
			keyed += 1
		if idx_of.has(rk):
			var ri: int = idx_of[rk]
			var rj: int = a.track_find_key(ri, t, Animation.FIND_MODE_EXACT)
			var rq: Quaternion = local.basis.get_rotation_quaternion()
			if rj != -1:
				a.track_set_key_value(ri, rj, rq)
			else:
				a.rotation_track_insert_key(ri, t, rq)
			keyed += 1
	# Tenue explicite (B2) : le player 4.7 ne tient pas la pose dans le vide
	# au-delà des clés (sondé : fin == T-pose). On matérialise le hold : la
	# valeur de la DERNIÈRE vraie clé est copiée à a.length (réécrite à
	# chaque key — find exact + set, jamais de doublon). Le keying rétroactif
	# (t avant la dernière clé) ne touche pas la tenue. Une ancienne tenue
	# dépassée par l'extension (t > length) devient une vraie clé de
	# transition (hold-then-move, correct).
	var held := 0
	for ti in a.get_track_count():
		var n: int = a.track_get_key_count(ti)
		if n == 0:
			continue
		var last_real := t
		for k in n:
			var kt: float = a.track_get_key_time(ti, k)
			if kt < a.length - 0.0005 and kt > last_real:
				last_real = kt
		if t < last_real - 0.0005:
			continue
		var kv = a.track_get_key_value(ti, a.track_find_key(ti, t, Animation.FIND_MODE_EXACT))
		var kh: int = a.track_find_key(ti, a.length, Animation.FIND_MODE_EXACT)
		if kh != -1:
			a.track_set_key_value(ti, kh, kv)
		elif a.track_get_type(ti) == Animation.TYPE_POSITION_3D:
			a.position_track_insert_key(ti, a.length, kv)
		elif a.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
			a.rotation_track_insert_key(ti, a.length, kv)
		else:
			a.track_insert_key(ti, a.length, kv)
		held += 1
	print("[AnimCreator] keyed %s @ %.3fs (%d keys, %d held)" % [String(authored_clip), t, keyed, held])


## Base dict (skeleton-space globals) depuis le bind (pur, synchrone).
func _capture_rest_base() -> void:
	_base_pose.clear()
	var kids := {}
	for i in _skeleton.get_bone_count():
		var p := _skeleton.get_bone_parent(i)
		if not kids.has(p):
			kids[p] = []
		(kids[p] as Array).append(i)
	_accum_rest(-1, Transform3D.IDENTITY, kids)
	_base_name = "T-pose"


func _accum_rest(pidx: int, pt: Transform3D, kids: Dictionary) -> void:
	if not kids.has(pidx):
		return
	for i in kids[pidx]:
		var t: Transform3D = pt * _skeleton.get_bone_rest(i)
		_base_pose[_skeleton.get_bone_name(i)] = t
		_accum_rest(i, t, kids)


## Base dict depuis le live (take pausée affichée OU travail courant —
## writers effacés ou visual truth, les deux sont capturables).
func _capture_live_base() -> void:
	_base_pose.clear()
	for i in _skeleton.get_bone_count():
		_base_pose[_skeleton.get_bone_name(i)] = _skeleton.get_bone_global_pose(i)


## Dérive TOUTES les refs writers depuis _base_pose (maths pures, rig-
## invariant : quats monde via skBasis constant, offsets/lengths relatifs).
## Appelé au build (repos) et à chaque Set-as-base.
func _derive_base_refs() -> void:
	if _skeleton == null or _base_pose.is_empty():
		return
	var skb: Basis = _skeleton.global_transform.basis
	var wq := func(b: StringName) -> Quaternion:
		return (skb * (_base_pose[b] as Transform3D).basis).get_rotation_quaternion()
	var parent_of := {&"Spine": &"Hips", &"Chest": &"Spine", &"UpperChest": &"Chest", &"Neck": &"UpperChest", &"Head": &"Neck"}
	# Hips + chaînes bras/jambes (même dérivation, base unique).
	_hips_rest_w = wq.call(&"Hips")
	for limb in LIMB_ORDER:
		var bones: Dictionary = _bones_of(limb)
		var uw: Vector3 = ((_base_pose[bones["upper"]] as Transform3D).origin)
		var jw: Vector3 = ((_base_pose[bones["middle"]] as Transform3D).origin)
		var ew: Vector3 = ((_base_pose[bones["end"]] as Transform3D).origin)
		_chain_len[limb] = [uw.distance_to(jw), jw.distance_to(ew)]
		_chain_rest_w[limb] = {&"upper": wq.call(bones["upper"]), &"middle": wq.call(bones["middle"]), &"end": wq.call(bones["end"])}
		var up: Transform3D = _base_pose[bones["upper"]]
		var jp: Transform3D = _base_pose[bones["middle"]]
		_chain_len_local[limb] = {
			&"upper": (up.affine_inverse() * jp.origin).normalized(),
			&"middle": (jp.affine_inverse() * (_base_pose[bones["end"]] as Transform3D).origin).normalized(),
		}
		if LEG_BONES.has(limb):
			_hip_off[limb] = wq.call(&"Hips").inverse() * (skb * (uw - (_base_pose[&"Hips"] as Transform3D).origin))
			_ankle_rest[limb] = wq.call(bones["end"])
		# Bend-side + parité depuis la base (directions MONDE : skb × delta sk).
		var t10: Vector3 = (skb * (jw - uw)).normalized()
		var pole_dir: Vector3 = LEG_POLE_DIR if LEG_BONES.has(limb) else ARM_POLE_DIR
		var pole_w: Vector3 = (skb * pole_dir).normalized()
		var bref: Vector3 = t10.cross(pole_w)
		if bref.length() < 0.001:
			bref = Vector3(1, 0, 0)
		_chain_bend_ref[limb] = bref.normalized()
		var side := {}
		for key in [&"upper", &"middle"]:
			var q0: Quaternion = (_chain_rest_w[limb] as Dictionary)[key]
			var s: float = signf(((q0 * Vector3(1, 0, 0)).normalized()).dot(_chain_bend_ref[limb]))
			side[key] = s if s != 0.0 else 1.0
		_chain_side[limb] = side
	# Dos/cou : q monde + origine sk + offsets vs parent (base).
	for entry in TORSO_SPLIT + HEAD_SPLIT:
		var t: Transform3D = _base_pose[entry[0]]
		var q0: Quaternion = (skb * t.basis).get_rotation_quaternion()
		var pt: Transform3D = _base_pose[parent_of[entry[0]]]
		var pq: Quaternion = (skb * pt.basis).get_rotation_quaternion()
		_spine_rest[entry[0]] = {
			"q": q0,
			"o": t.origin,
			"off": (pq.inverse() * q0).normalized(),
			"poff": pq.inverse() * (skb * (t.origin - pt.origin)),
		}
	# Ancres pôles + rest-local poignet SUIVENT LA BASE (take figée ou
	# repos) : ancrés au bind, les pôles restaient décalés de (bind−take)
	# et le poignet reprenait l'orientation bind-relative (décalages
	# post-capture à handles fixes). Longueurs inchangées (même squelette).
	for limb in LIMB_ORDER:
		var bb: Dictionary = _bones_of(limb)
		_joint_rest[limb] = (_base_pose[bb["middle"]] as Transform3D).origin
		_upper_rest[limb] = (_base_pose[bb["upper"]] as Transform3D).origin
	for side in ARM_BONES:
		var rw_side: Dictionary = _chain_rest_w[side]
		_wrist_rest_local[side] = ((rw_side[&"middle"] as Quaternion).inverse() * (rw_side[&"end"] as Quaternion)).normalized()
	# Bras : 2-hop chain (upper ← hop1 ← hop2, noms résolus au build) pour
	# une racine SANS lecture live (REV 23 : le read reportait notre propre
	# override persistant → latch take auto-entretenu, comme les hanches).
	for limb in ARM_BONES:
		var bones: Dictionary = ARM_BONES[limb]
		var u_idx := _skeleton.find_bone(bones["upper"])
		var h1_idx := _skeleton.get_bone_parent(u_idx) if u_idx != -1 else -1
		var h2_idx := _skeleton.get_bone_parent(h1_idx) if h1_idx != -1 else -1
		if u_idx == -1 or h1_idx == -1 or h2_idx == -1:
			continue
		var h1n := _skeleton.get_bone_name(h1_idx)
		var h2n := _skeleton.get_bone_name(h2_idx)
		var q2: Quaternion = (skb * (_base_pose[h2n] as Transform3D).basis).get_rotation_quaternion()
		var q1: Quaternion = (skb * (_base_pose[h1n] as Transform3D).basis).get_rotation_quaternion()
		var o2: Vector3 = (_base_pose[h2n] as Transform3D).origin
		var o1: Vector3 = (_base_pose[h1n] as Transform3D).origin
		var ou: Vector3 = (_base_pose[bones["upper"]] as Transform3D).origin
		_arm_hop[limb] = {
			"h2": h2n,
			"off1": q2.inverse() * (skb * (o1 - o2)),
			"rel1": (q2.inverse() * q1).normalized(),
			"offU": q1.inverse() * (skb * (ou - o1)),
		}


## Recale les handles positionnels sur la pose live (take figée) : mains,
## pieds, hanches, genoux → articulations. Proxies snappés (pas de chase).
## Rotations cubes intactes (deltas relatifs au repos handle, base-indépendants).
func _snap_handles_to_live() -> void:
	if _skeleton == null:
		return
	var joint_of := {&"Left": &"LeftHand", &"Right": &"RightHand", &"LeftLeg": &"LeftFoot", &"RightLeg": &"RightFoot"}
	for limb in joint_of:
		var bidx := _skeleton.find_bone(joint_of[limb])
		if bidx != -1 and _handles.has(limb):
			(_handles[limb] as Node3D).global_position = _skeleton.to_global(_skeleton.get_bone_global_pose(bidx).origin)
			if _proxy.has(limb):
				(_proxy[limb] as Node3D).global_position = (_handles[limb] as Node3D).global_position
	for leg in LEG_BONES:
		var kidx := _skeleton.find_bone((LEG_BONES[leg] as Dictionary)["middle"])
		if kidx != -1 and _knee.has(leg):
			(_knee[leg] as Node3D).global_position = _skeleton.to_global(_skeleton.get_bone_global_pose(kidx).origin)
			_knee_rest_pos[leg] = (_knee[leg] as Node3D).global_position
	var hips_idx := _skeleton.find_bone(&"Hips")
	if hips_idx != -1 and _hips != null:
		_hips.global_position = _skeleton.to_global(_skeleton.get_bone_global_pose(hips_idx).origin)


## Bouton Set as base : capture la pose VISIBLE telle quelle au prochain
## frame (take figée au playhead du dock OU travail courant), puis fige les
## non-authorés, décharge, writers reprennent. Ne touche JAMAIS au player
## avant la capture : après un pause-dock 4.7 current est vidé et take_frame
## peut être stale — tout play/seek pré-capture réinitialiserait la pose à
## t0 et détruirait le gel du dock (bug 26/09). Sans take : rebase itératif.
func set_as_base() -> void:
	if _skeleton == null:
		push_warning("[AnimCreator] set-as-base: rig not built")
		return
	var f: int = take_frame
	if _take_player != null and _take_player.current_animation != &"":
		f = int(round(_take_player.get_current_animation_position() * 60.0))
	_base_name = ("%s f%d" % [String(take_name), f]) if not _take_current.is_empty() else "work"
	if _take_player != null and _take_player.is_playing():
		_take_player.pause()
	_pending_base = true
	print("[AnimCreator] capturing base next frame…")


## Bouton T-pose : base = bind (pur), statics effacés, take déchargée,
## handles reset + zéro steering ré-ancré sur le bind (le snap take l'avait
## déplacé — sinon les cubes genoux restent à la take après reset).
func set_tpose_base() -> void:
	if _skeleton == null:
		return
	_unload_take()
	take_playing = false
	_pole_dir_cap.clear()
	_capture_rest_base()
	_derive_base_refs()
	_apply_override_clear()
	reset_handles()
	for leg in LEG_BONES:
		if _knee.has(leg) and _joint_rest.has(leg):
			(_knee[leg] as Node3D).global_position = _skeleton.to_global(_joint_rest[leg] as Vector3)
			_knee_rest_pos[leg] = (_knee[leg] as Node3D).global_position
	print("[AnimCreator] base = T-pose")


## Fige les os NON authorés sur la pose visible (take figée) — WYSIWYG :
## tout ce que l'humain voit est cléable ensuite.
func _write_base_statics() -> void:
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		if (_authored_names as Array).has(_skeleton.get_bone_name(i)):
			continue
		_skeleton.set_bone_global_pose_override(i, _skeleton.get_bone_global_pose(i), 1.0, true)


func _find_skeleton() -> Skeleton3D:
	var rig := get_node_or_null("RigRoot")
	if rig == null:
		return null
	var direct := rig.get_node_or_null("Armature/GeneralSkeleton") as Skeleton3D
	if direct != null:
		return direct
	var found := rig.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


## Frees previously built runtime modifiers (hot-reload / re-entry safety).
## Keeps every historical suffix so stale pre-REV23 TwoBone nodes get collected.
func _clear_modifiers() -> void:
	if _skeleton == null:
		return
	for child in _skeleton.get_children():
		if child is SkeletonModifier3D and (str(child.name).ends_with("HandIK") or str(child.name).ends_with("LimbIK") or str(child.name).ends_with("FabrikArm") or str(child.name).ends_with("FabrikLeg") or str(child.name).ends_with("FootIK") or str(child.name).ends_with("TwistDisperse")):
			_skeleton.remove_child(child)
			child.queue_free()


## Frees previously built internal auto-poles AND proxies.
func _clear_auto_poles() -> void:
	for limb in _poles:
		var p: Node3D = _poles[limb]
		if is_instance_valid(p):
			remove_child(p)
			p.queue_free()
	_poles.clear()
	for limb in _proxy:
		var t: Node3D = _proxy[limb]
		if is_instance_valid(t):
			remove_child(t)
			t.queue_free()
	_proxy.clear()


## Rest snapshot (spike formula): end/joint/root rest + reach.
## The joint-side reference is read live from the pole node (gizmo-moved),
## never snapshotted. Handles keep their scene positions.
func _snapshot_rest(limb: StringName) -> void:
	var bones: Dictionary = _bones_of(limb)
	var upper_idx := _skeleton.find_bone(bones["upper"])
	var end_idx := _skeleton.find_bone(bones["end"])
	var joint_idx := _skeleton.find_bone(bones["middle"])
	var root_idx := _skeleton.find_bone(bones["shoulder"])
	if upper_idx == -1 or end_idx == -1 or joint_idx == -1 or root_idx == -1:
		push_error("[AnimCreator] limb bones missing: %s" % String(limb))
		return
	var end_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(end_idx).origin)
	var joint_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(joint_idx).origin)
	var root_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(root_idx).origin)
	_rest[limb] = _skeleton.to_local(end_w)
	_joint_rest[limb] = _skeleton.to_local(joint_w)
	_shoulder_rest[limb] = _skeleton.to_local(root_w)
	_upper_rest[limb] = _skeleton.to_local(_skeleton.to_global(_skeleton.get_bone_global_pose(upper_idx).origin))
	_reach[limb] = root_w.distance_to(end_w)
	# Bow reference = anatomical pole side (skeleton space). Kept in sync with
	# the adaptive pole each frame (see _update_auto_poles); the build-time
	# value below is just the rest fallback.
	if root_w.distance_to(end_w) > 0.001:
		var off := LEG_POLE_DIR if LEG_BONES.has(limb) else ARM_POLE_DIR
		_bow_ref[limb] = (_skeleton.global_transform.basis.inverse() * off).normalized()


## Set des os authorés (tout le reste suit la base en statique) : chaînes
## bras/jambes + Hips + colonne. Construit une fois (noms statiques).
func _build_authored_set() -> void:
	_authored_names.clear()
	_authored_names.append(&"Hips")
	for table in [ARM_BONES, LEG_BONES]:
		for limb in table:
			var bones: Dictionary = table[limb]
			_authored_names.append(bones["upper"])
			_authored_names.append(bones["middle"])
			_authored_names.append(bones["end"])
	for entry in TORSO_SPLIT + HEAD_SPLIT:
		_authored_names.append(entry[0])


## Custom analytic leg solve (STATELESS — pure function of live inputs).
## Law of cosines for positions (honest stretch past reach, like TwoBone),
## explicit basis construction for orientations: shortest-arc length mapping
## (minimal roll vs rest) + roll correction enforcing the anatomical bend
## side (constant ref). The TwoBone 140° bistability cannot occur: same
## inputs → same outputs, clean branch by construction. Runs pre-pipeline
## in _process (same frame, stateless); remplit les mêmes dicts
## métriques/seams pour trace + bake guard.
func _solve_leg(limb: StringName) -> void:
	if not _chain_len.has(limb) or not _proxy.has(limb) or not _poles.has(limb):
		return
	var bones: Dictionary = LEG_BONES[limb]
	var u_idx := _skeleton.find_bone(bones["upper"])
	var j_idx := _skeleton.find_bone(bones["middle"])
	var e_idx := _skeleton.find_bone(bones["end"])
	var r_idx := _skeleton.find_bone(bones["shoulder"])
	if u_idx == -1 or j_idx == -1 or e_idx == -1 or r_idx == -1:
		return
	var lens: Array = _chain_len[limb]
	var l1: float = lens[0]
	var l2: float = lens[1]
	var reach: float = l1 + l2
	# Haut-cuisse threadé du bassin résolu (le tilt déplace les hanches).
	var h_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(u_idx).origin)
	if _hip_off.has(limb):
		h_w = _hips_sp + _hips_sq * (_hip_off[limb] as Vector3)
	var root_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(r_idx).origin)
	var target_w: Vector3 = (_proxy[limb] as Node3D).global_position
	var pole_w: Vector3 = (_poles[limb] as Node3D).global_position
	var axis: Vector3 = target_w - h_w
	var d: float = axis.length()
	if d < 0.0001:
		return
	var dir: Vector3 = axis / d
	# Honest stretch: foot stops at reach, err carries the over-reach.
	var dist: float = minf(d, reach)
	var f_w: Vector3 = h_w + dir * dist
	_err[limb] = maxf(0.0, d - reach)
	# Knee: law of cosines (angle at hip) + pole-side height.
	var cos_a := 1.0
	if dist > 0.0001 and l1 > 0.0001:
		cos_a = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a: float = sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var n: Vector3 = (pole_w - h_w) - dir * ((pole_w - h_w).dot(dir))
	if n.length() < 0.0001:
		var bref: Vector3 = _chain_bend_ref[limb]
		n = bref - dir * (bref.dot(dir))
	if n.length() < 0.0001:
		n = Vector3(0, 0, 1) - dir * dir.z
	n = n.normalized()
	var k_w: Vector3 = h_w + (dir * cos_a + n * sin_a) * l1
	var t1: Vector3 = (k_w - h_w) / maxf(l1, 0.0001)
	var t2: Vector3 = (f_w - k_w) / maxf(l2, 0.0001)
	if t2.length() < 0.5:
		t2 = dir
	else:
		t2 = t2.normalized()
	# Bend axis, sign-enforced to the anatomical side (THE anti-flip lock).
	var bend: Vector3 = t1.cross(t2)
	var bref2: Vector3 = _chain_bend_ref[limb]
	if bend.length() < 0.0001:
		bend = bref2 - t1 * (bref2.dot(t1))
	if bend.length() < 0.0001:
		bend = Vector3(1, 0, 0) - t1 * t1.x
	bend = bend.normalized()
	if bend.dot(bref2) < 0.0:
		bend = -bend
	var sk_basis: Basis = _skeleton.global_transform.basis
	var sk_inv: Basis = sk_basis.inverse()
	var rw: Dictionary = _chain_rest_w[limb]
	var ll: Dictionary = _chain_len_local[limb]
	# Thigh + shin orientations: shortest-arc length map × roll correction.
	# Per-bone side (bind parity): each bone's X returns to its own rest side.
	var side: Dictionary = _chain_side[limb]
	var q_thigh: Quaternion = _aim_bone(rw[&"upper"], ll[&"upper"], t1, bend * float(side.get(&"upper", 1.0)))
	var q_shin: Quaternion = _aim_bone(rw[&"middle"], ll[&"middle"], t2, bend * float(side.get(&"middle", 1.0)))
	# Skeleton-space override targets (same space as the wrist writer).
	# Le haut-cuisse part du bassin résolu (origine monde → skeleton space).
	var thigh_pos_sk: Vector3 = _skeleton.global_transform.affine_inverse() * h_w
	var thigh_sk := Transform3D(Basis(sk_inv * Basis(q_thigh)), thigh_pos_sk)
	var shin_pos_sk: Vector3 = (thigh_sk * _skeleton.get_bone_rest(j_idx)).origin
	var shin_sk := Transform3D(Basis(sk_inv * Basis(q_shin)), shin_pos_sk)
	var foot_pos_sk: Vector3 = (shin_sk * _skeleton.get_bone_rest(e_idx)).origin
	_skeleton.set_bone_global_pose_override(u_idx, thigh_sk, 1.0, true)
	_skeleton.set_bone_global_pose_override(j_idx, shin_sk, 1.0, true)
	_solve_pos[limb] = foot_pos_sk
	_solve_upper[limb] = q_thigh
	_solve_middle[limb] = q_shin
	# Foot orientation: ankle ON = world-flat × cube delta (ankle writer
	# consumes _solve_pos, unchanged); OFF = follow the shin (rest-local
	# offset carried — relative mode like the wrist).
	var handle: Node3D = _handles[limb]
	var hq: Quaternion = handle.global_transform.basis.get_rotation_quaternion()
	var h0: Quaternion = _handle_rest_rot.get(limb, Quaternion())
	var delta: Quaternion = h0.inverse() * hq
	var foot_q: Quaternion
	if ankle_copy:
		foot_q = (_ankle_rest[limb] as Quaternion) * delta
	else:
		var q_shin0: Quaternion = rw[&"middle"]
		var q_foot0: Quaternion = rw[&"end"]
		foot_q = q_shin * (q_shin0.inverse() * q_foot0) * delta
	_solve_end[limb] = foot_q
	if not ankle_copy:
		_skeleton.set_bone_global_pose_override(e_idx, Transform3D(Basis(sk_inv * Basis(foot_q)), foot_pos_sk), 1.0, true)
	# Metrics — mêmes formules bras/jambes (parité par construction).
	_prox[limb] = f_w.distance_to(root_w)
	_flex[limb] = rad_to_deg((k_w - root_w).angle_to(f_w - k_w))
	var chain_w: Vector3 = h_w
	var pole: Node3D = _poles[limb]
	var ref_v: Vector3 = (pole.global_position - chain_w).normalized()
	var dv: Vector3 = (k_w - chain_w).normalized()
	_dot[limb] = ref_v.dot(dv)
	var lax: Vector3 = f_w - root_w
	if lax.length() > 0.001 and _bow_ref.has(limb):
		var ldir: Vector3 = lax.normalized()
		var off_world: Vector3 = (k_w - root_w) - ldir * ((k_w - root_w).dot(ldir))
		var off_sk: Vector3 = sk_basis.inverse() * off_world
		_bow[limb] = off_sk.dot(_bow_ref[limb] as Vector3)


## Point résolu (monde : [quat, pos]) d'un os hors-membres : colonne résolue
## même frame si spine, sinon base (non-authorés = statics figés ou bind —
## toujours la base par construction). Zéro lecture live, zéro latch.
func _chain_point(bn: StringName) -> Array:
	if _spine_solved_quat.has(bn) and _spine_solved_pos.has(bn):
		return [_spine_solved_quat[bn] as Quaternion, _spine_solved_pos[bn] as Vector3]
	if _skeleton == null or _base_pose.is_empty() or not _base_pose.has(bn):
		return [Quaternion(), Vector3.ZERO]
	var skb: Basis = _skeleton.global_transform.basis
	var t: Transform3D = _base_pose[bn]
	return [(skb * t.basis).get_rotation_quaternion(), _skeleton.to_global(t.origin)]


## Custom analytic arm solve (STATELESS — même noyau que _solve_leg).
## Haut-bras live (pas de threading bassin : l'épaule suit le torse avec 1
## frame de lag, comme les pôles auto) ; métriques vs l'os épaule. Remplit
## _solve_pos/_solve_fore pour le writer poignet (relatif au bras, inchangé)
## + orientations/métriques pour trace et bake guard. La main est écrite par
## _apply_stored_wrist (site unique), pas ici.
func _solve_arm(limb: StringName) -> void:
	if not _chain_len.has(limb) or not _proxy.has(limb) or not _poles.has(limb):
		return
	var bones: Dictionary = ARM_BONES[limb]
	var u_idx := _skeleton.find_bone(bones["upper"])
	var j_idx := _skeleton.find_bone(bones["middle"])
	var e_idx := _skeleton.find_bone(bones["end"])
	var r_idx := _skeleton.find_bone(bones["shoulder"])
	if u_idx == -1 or j_idx == -1 or e_idx == -1 or r_idx == -1:
		return
	var lens: Array = _chain_len[limb]
	var l1: float = lens[0]
	var l2: float = lens[1]
	var reach: float = l1 + l2
	# Racine SANS lecture live (le read verrait notre override persistant du
	# frame précédent → latch) : composée depuis hop2 résolu (colonne même
	# frame, sinon base) + offsets base. root = hop1 (os parent du bras).
	if not _arm_hop.has(limb):
		return
	var hop: Dictionary = _arm_hop[limb]
	var bp: Array = _chain_point(hop["h2"])
	var q_h2: Quaternion = bp[0]
	var p_h2: Vector3 = bp[1]
	var q_h1: Quaternion = (q_h2 * (hop["rel1"] as Quaternion)).normalized()
	var p_h1: Vector3 = p_h2 + q_h2 * (hop["off1"] as Vector3)
	var h_w: Vector3 = p_h1 + q_h1 * (hop["offU"] as Vector3)
	var root_w: Vector3 = p_h1
	var target_w: Vector3 = (_proxy[limb] as Node3D).global_position
	var pole_w: Vector3 = (_poles[limb] as Node3D).global_position
	var axis: Vector3 = target_w - h_w
	var d: float = axis.length()
	if d < 0.0001:
		return
	var dir: Vector3 = axis / d
	var dist: float = minf(d, reach)
	var f_w: Vector3 = h_w + dir * dist
	_err[limb] = maxf(0.0, d - reach)
	var cos_a := 1.0
	if dist > 0.0001 and l1 > 0.0001:
		cos_a = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a: float = sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var n: Vector3 = (pole_w - h_w) - dir * ((pole_w - h_w).dot(dir))
	if n.length() < 0.0001:
		var bref: Vector3 = _chain_bend_ref[limb]
		n = bref - dir * (bref.dot(dir))
	if n.length() < 0.0001:
		n = Vector3(0, 0, -1) - dir * dir.z
	n = n.normalized()
	var k_w: Vector3 = h_w + (dir * cos_a + n * sin_a) * l1
	var t1: Vector3 = (k_w - h_w) / maxf(l1, 0.0001)
	var t2: Vector3 = (f_w - k_w) / maxf(l2, 0.0001)
	if t2.length() < 0.5:
		t2 = dir
	else:
		t2 = t2.normalized()
	var bend: Vector3 = t1.cross(t2)
	var bref2: Vector3 = _chain_bend_ref[limb]
	if bend.length() < 0.0001:
		bend = bref2 - t1 * (bref2.dot(t1))
	if bend.length() < 0.0001:
		bend = Vector3(1, 0, 0) - t1 * t1.x
	bend = bend.normalized()
	if bend.dot(bref2) < 0.0:
		bend = -bend
	var sk_basis: Basis = _skeleton.global_transform.basis
	var sk_inv: Basis = sk_basis.inverse()
	var rw: Dictionary = _chain_rest_w[limb]
	var ll: Dictionary = _chain_len_local[limb]
	var side: Dictionary = _chain_side[limb]
	var q_upper: Quaternion = _aim_bone(rw[&"upper"], ll[&"upper"], t1, bend * float(side.get(&"upper", 1.0)))
	var q_fore: Quaternion = _aim_bone(rw[&"middle"], ll[&"middle"], t2, bend * float(side.get(&"middle", 1.0)))
	var upper_pos_sk: Vector3 = _skeleton.global_transform.affine_inverse() * h_w
	var upper_sk := Transform3D(Basis(sk_inv * Basis(q_upper)), upper_pos_sk)
	var fore_pos_sk: Vector3 = (upper_sk * _skeleton.get_bone_rest(j_idx)).origin
	var fore_sk := Transform3D(Basis(sk_inv * Basis(q_fore)), fore_pos_sk)
	var hand_pos_sk: Vector3 = (fore_sk * _skeleton.get_bone_rest(e_idx)).origin
	_skeleton.set_bone_global_pose_override(u_idx, upper_sk, 1.0, true)
	_skeleton.set_bone_global_pose_override(j_idx, fore_sk, 1.0, true)
	_solve_pos[limb] = hand_pos_sk
	_solve_fore[limb] = q_fore
	_solve_upper[limb] = q_upper
	_solve_middle[limb] = q_fore
	_prox[limb] = f_w.distance_to(root_w)
	_flex[limb] = rad_to_deg((k_w - root_w).angle_to(f_w - k_w))
	var chain_w: Vector3 = h_w
	var pole: Node3D = _poles[limb]
	var ref_v: Vector3 = (pole.global_position - chain_w).normalized()
	var dv: Vector3 = (k_w - chain_w).normalized()
	_dot[limb] = ref_v.dot(dv)
	var lax: Vector3 = f_w - root_w
	if lax.length() > 0.001 and _bow_ref.has(limb):
		var ldir: Vector3 = lax.normalized()
		var off_world: Vector3 = (k_w - root_w) - ldir * ((k_w - root_w).dot(ldir))
		var off_sk: Vector3 = sk_basis.inverse() * off_world
		_bow[limb] = off_sk.dot(_bow_ref[limb] as Vector3)


## Bone aiming helper: rest orientation carried by shortest-arc length map,
## then roll-corrected so local X lands on the enforced bend axis.
## Deterministic, continuous, minimal roll — the anti-bistability core.
func _aim_bone(q_rest0: Quaternion, l_local: Vector3, t_world: Vector3, bend_world: Vector3) -> Quaternion:
	var l_w0: Vector3 = (q_rest0 * l_local).normalized()
	var q1 := Quaternion(l_w0, t_world)
	var x1: Vector3 = (q1 * q_rest0) * Vector3(1, 0, 0)
	var ang: float = atan2(x1.cross(bend_world).dot(t_world), x1.dot(bend_world))
	var q_roll := Quaternion(t_world, ang)
	return (q_roll * q1 * q_rest0).normalized()


## Capture le côté de pli réel de la pose live (take figée ou travail) :
## lit les origines monde des os (vérité mixer si take, vérité overrides si
## travail — dans les deux cas la pose visible), projette le joint hors de
## l'axe racine→cible. Seuil 1 cm : membre quasi-tendu → anatomique.
func _capture_pole_dirs() -> void:
	if _skeleton == null or _proxy.is_empty():
		return
	var skb: Basis = _skeleton.global_transform.basis
	for limb in LIMB_ORDER:
		if not _proxy.has(limb):
			continue
		var bones: Dictionary = _bones_of(limb)
		var u_idx := _skeleton.find_bone(bones["upper"])
		var j_idx := _skeleton.find_bone(bones["middle"])
		if u_idx == -1 or j_idx == -1:
			continue
		var root_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(u_idx).origin)
		var joint_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(j_idx).origin)
		var target_w: Vector3 = (_proxy[limb] as Node3D).global_position
		var axis: Vector3 = target_w - root_w
		if axis.length() < 0.05:
			_pole_dir_cap.erase(limb)
			continue
		var along: Vector3 = axis.normalized()
		var eperp: Vector3 = (joint_w - root_w) - along * (joint_w - root_w).dot(along)
		if eperp.length() > 0.01:
			_pole_dir_cap[limb] = (skb.inverse() * eperp.normalized()).normalized()
		else:
			_pole_dir_cap.erase(limb)


## Auto-pole placement (the constraint, pre-pipeline like the hips follow).
## pole = joint-rest world pos + ADAPTED anatomical direction × POLE_DIST,
## where the direction = the anatomical forward/backward re-projected
## perpendicular to the live chain-root→target line. Rest-anchored poles let
## the line rotate onto them on large excursions (degenerate plane → random
## knee side); adapted poles can never lie on the line. Near-degenerate input
## (straight horizontal kick along the anatomical axis) keeps the previous
## pole (hysteresis, no snap). All inputs are stored locals + live node
## transforms — no bone reads, no solver feedback.
func _update_auto_poles() -> void:
	if _skeleton == null or _poles.is_empty() or _joint_rest.is_empty():
		return
	for limb in LIMB_ORDER:
		if not _poles.has(limb) or not _joint_rest.has(limb) or not _upper_rest.has(limb) or not _proxy.has(limb):
			continue
		var fwd := ARM_POLE_DIR
		if _pole_dir_cap.has(limb):
			fwd = (_skeleton.global_transform.basis * (_pole_dir_cap[limb] as Vector3)).normalized()
		elif LEG_BONES.has(limb):
			var side_sign := 1.0 if String(limb).begins_with("Left") else -1.0
			fwd = Vector3(side_sign * LEG_POLE_LAT, 0.0, 1.0).normalized()
		var root_w: Vector3 = _skeleton.to_global(_upper_rest[limb] as Vector3)
		# Jambes : le haut des cuisses suit le tilt du bassin (threadé).
		if LEG_BONES.has(limb) and _hip_off.has(limb):
			root_w = _hips_sp + _hips_sq * (_hip_off[limb] as Vector3)
		var target_w: Vector3 = (_proxy[limb] as Node3D).global_position
		var line: Vector3 = target_w - root_w
		if line.length() < 0.05:
			continue
		var along: Vector3 = line.normalized()
		var perp: Vector3 = fwd - along * fwd.dot(along)
		if perp.length() < 0.05:
			continue
		var dir: Vector3 = perp.normalized()
		var pole_node: Node3D = _poles[limb]
		pole_node.global_position = _skeleton.to_global(_joint_rest[limb] as Vector3) + dir * POLE_DIST
		# Knee steering (phase 2) : l'offset du handle genou décale le pôle
		# (borné) — le genou suit dans son cercle, le plan reste épinglé par
		# construction. Zéro = pôle auto pur (parité exacte).
		if LEG_BONES.has(limb) and knee_copy and _knee.has(limb):
			var off: Vector3 = (_knee[limb] as Node3D).global_position - (_knee_rest_pos.get(limb, (_knee[limb] as Node3D).global_position) as Vector3)
			if off.length() > KNEE_OFF_MAX:
				off = off.normalized() * KNEE_OFF_MAX
			pole_node.global_position += off
		_bow_ref[limb] = (_skeleton.global_transform.basis.inverse() * (pole_node.global_position - _skeleton.to_global(_joint_rest[limb] as Vector3)).normalized()).normalized()


## Step 2 wrist follow (code-driven override, same frame que le solveur) :
## _solve_arm remplit _solve_pos (origine main, skeleton space) + _solve_fore
## (rotation monde de l'avant-bras), et _apply_stored_wrist écrit la main.
## Position = origine solveur honnête (stretch visible) ; rotation = parent
## × rest-local bind × delta cube (poignet relatif au bras). Pas de lecture
## de la main, pas de feedback (le parent n'est jamais overridé).


## Override write (pre-pipeline _process, from the stored snapshot): the hand
## keeps the honest solver position and takes its orientation from the live
## parent bone × the bind rest-local × the cube delta — i.e. the wrist is
## relative to the arm (fingers follow the forearm when translating, like a
## real wrist), plus the authored cube rotation on top. No read-back of the
## hand, no feedback loop (the parent is never overridden).
func _apply_stored_wrist() -> void:
	if _skeleton == null or _handles.is_empty() or not wrist_copy:
		return
	if _solve_pos.is_empty():
		return
	for side in ARM_BONES:
		if not _solve_pos.has(side) or not _solve_fore.has(side) or not _handles.has(side):
			continue
		var handle: Node3D = _handles[side]
		var hq: Quaternion = handle.global_transform.basis.get_rotation_quaternion()
		var h0: Quaternion = _handle_rest_rot.get(side, Quaternion())
		var delta: Quaternion = h0.inverse() * hq
		var hand_idx := _skeleton.find_bone((ARM_BONES[side] as Dictionary)["end"])
		if hand_idx == -1:
			continue
		# Wrist relative to the arm: live parent × BASE rest-local × delta
		# (base = repos ou take figée — jamais le bind, cf. _derive_base_refs).
		var rest_local: Quaternion = _wrist_rest_local.get(side, _skeleton.get_bone_rest(hand_idx).basis.get_rotation_quaternion())
		var world_q: Quaternion = (_solve_fore[side] as Quaternion) * rest_local * delta
		var sk_q: Quaternion = _skeleton.global_transform.basis.get_rotation_quaternion()
		var target := Transform3D(Basis(sk_q.inverse() * world_q * sk_q), _solve_pos[side] as Vector3)
		_skeleton.set_bone_global_pose_override(hand_idx, target, 1.0, true)
		_solve_end[side] = world_q


## Override write (pre-pipeline _process, same split as the wrist): the foot
## keeps the honest solver position and takes its orientation from the REST
## world orientation × the cube delta — i.e. the ankle is world-flat by
## default (planted foot), plus the authored cube rotation on top (pointe,
## angled stomps). Unlike the wrist this is NOT relative to the parent: the
## chain-dictated orientation is exactly what flips the toes (measured 180°
## on crouch+step), so the parent must not contribute. No read-back of the
## foot, no feedback loop (le solveur custom est stateless — mêmes inputs,
## mêmes outputs, jamais de lecture d'override).
func _apply_stored_ankle() -> void:
	if _skeleton == null or _handles.is_empty() or not ankle_copy:
		return
	if _solve_pos.is_empty():
		return
	var sk_q: Quaternion = _skeleton.global_transform.basis.get_rotation_quaternion()
	for limb in LEG_BONES:
		if not _solve_pos.has(limb) or not _handles.has(limb) or not _ankle_rest.has(limb):
			continue
		var handle: Node3D = _handles[limb]
		var hq: Quaternion = handle.global_transform.basis.get_rotation_quaternion()
		var h0: Quaternion = _handle_rest_rot.get(limb, Quaternion())
		var delta: Quaternion = h0.inverse() * hq
		var foot_idx := _skeleton.find_bone((LEG_BONES[limb] as Dictionary)["end"])
		if foot_idx == -1:
			continue
		# Base (repos ou take figée) × authored delta, back to skeleton space.
		var world_q: Quaternion = (_ankle_rest[limb] as Quaternion) * delta
		var target := Transform3D(Basis(sk_q.inverse() * world_q), _solve_pos[limb] as Vector3)
		_skeleton.set_bone_global_pose_override(foot_idx, target, 1.0, true)


## Torso/head writes (pre-pipeline _process, chaîne CONSCIENTE : chaque os
## part du parent PORTÉ (résolu même frame, overridé ou non) × offset
## rest-local × fraction du delta. Le torse penché porte donc nuque et tête
## (bug 25/09 : writer tête sur base rest = nuque épinglée, cou étiré).
## Départ = bassin RÉSOLU (tilt threadé). Toggles = gate d'ÉCRITURE seule
## (résolution toujours calculée pour chaîner).
## Positions = rest (les vertèbres tournent sur place). Zéro = repos.
func _apply_spine() -> void:
	if _skeleton == null or _torso == null or _head == null:
		return
	if _spine_rest.is_empty():
		return
	var sk_q: Quaternion = _skeleton.global_transform.basis.get_rotation_quaternion()
	var sk_inv: Transform3D = _skeleton.global_transform.affine_inverse()
	# Départ = bassin résolu (tilt du pelvis inclus, calculé par _solve_hips).
	var parent_q: Quaternion = _hips_sq
	var parent_p: Vector3 = _hips_sp
	var tdelta: Quaternion = _torso_rest_rot.inverse() * _torso.global_transform.basis.get_rotation_quaternion()
	for entry in TORSO_SPLIT:
		var ref: Dictionary = _spine_rest[entry[0]]
		var q: Quaternion = (parent_q * (ref["off"] as Quaternion) * Quaternion().slerp(tdelta, float(entry[1]))).normalized()
		var p: Vector3 = parent_p + parent_q * (ref["poff"] as Vector3)
		parent_q = q
		parent_p = p
		_spine_solved_pos[entry[0]] = p
		_spine_solved_quat[entry[0]] = q
		if not torso_copy:
			continue
		var idx := _skeleton.find_bone(entry[0])
		if idx == -1:
			continue
		_skeleton.set_bone_global_pose_override(idx, Transform3D(Basis(sk_q.inverse() * q), sk_inv * p), 1.0, true)
	var hdelta: Quaternion = _head_rest_rot.inverse() * _head.global_transform.basis.get_rotation_quaternion()
	for entry in HEAD_SPLIT:
		var ref: Dictionary = _spine_rest[entry[0]]
		var q: Quaternion = (parent_q * (ref["off"] as Quaternion) * Quaternion().slerp(hdelta, float(entry[1]))).normalized()
		var p: Vector3 = parent_p + parent_q * (ref["poff"] as Vector3)
		parent_q = q
		parent_p = p
		_spine_solved_pos[entry[0]] = p
		_spine_solved_quat[entry[0]] = q
		if not head_copy:
			continue
		var idx := _skeleton.find_bone(entry[0])
		if idx == -1:
			continue
		_skeleton.set_bone_global_pose_override(idx, Transform3D(Basis(sk_q.inverse() * q), sk_inv * p), 1.0, true)


## Override toggles (A/B proofs): turning anything OFF clears ALL overrides
## first (stale persistent locks otherwise survive toggle-off and pin bones —
## measured 25/09: thigh lock froze the leg with the writer disabled). The
## per-frame writers below re-assert the enabled ones on the next frame, so
## clearing is always self-healing. Only our overrides live on this skeleton.
func _apply_override_clear() -> void:
	if _skeleton == null:
		return
	_skeleton.clear_bones_global_pose_override()


func set_wrist_copy(v: bool) -> void:
	wrist_copy = v
	_apply_override_clear()


func set_ankle_copy(v: bool) -> void:
	ankle_copy = v
	_apply_override_clear()


## Bassin résolu (pré-pipeline, avant pôles/jambes/dos) : orientation = base
## × delta handle (identité si toggle off → parité exacte), position = base
## (rotation sur place — la translation du bassin passe par le RigRoot, pas
## l'os). Origine BASE-DÉRIVÉE, jamais live-read (REV 23 : le report live
## verrouillait le résidu take/unload — _hips_sp restait figé à l'offset de
## la take après round-trip, genoux pliés + err bras fantômes).
func _solve_hips() -> void:
	if _skeleton == null or _hips == null or _hip_off.is_empty() or _base_pose.is_empty():
		return
	var delta: Quaternion = Quaternion()
	if pelvis_copy:
		delta = _hips_rest_rot.inverse() * _hips.global_transform.basis.get_rotation_quaternion()
	# Base (repos ou take figée) × delta handle — la take ne joue plus en
	# dessous, elle est figée dans la base par Set-as-base.
	var hbase: Quaternion = _hips_rest_w
	_hips_sq = (hbase * delta).normalized()
	var hips_idx := _skeleton.find_bone(&"Hips")
	if hips_idx == -1:
		return
	var hbase_pos_sk: Vector3 = (_base_pose[&"Hips"] as Transform3D).origin
	_hips_sp = _skeleton.to_global(hbase_pos_sk)
	if pelvis_copy:
		var sk_q: Quaternion = _skeleton.global_transform.basis.get_rotation_quaternion()
		_skeleton.set_bone_global_pose_override(hips_idx, Transform3D(Basis(sk_q.inverse() * _hips_sq), hbase_pos_sk), 1.0, true)


func _process(delta: float) -> void:
	# Slew FIRST (pre-pipeline): proxies ease toward user handles and the rig
	# toward the hips handle at SLEW_SPEED (frame-rate independent). Capped
	# per-frame inputs keep motion transients invisible; static poses settle
	# exact. Rotations stay direct (stateless overrides, immune).
	var step: float = SLEW_SPEED * maxf(delta, 0.0001)
	for limb in LIMB_ORDER:
		if _proxy.has(limb) and _handles.has(limb):
			var px: Node3D = _proxy[limb]
			var hx: Vector3 = (_handles[limb] as Node3D).global_position
			var d: Vector3 = hx - px.global_position
			px.global_position = hx if d.length() <= step else px.global_position + d.normalized() * step
	# Miroir dock → exports (sélection/scrub/play du PreviewPlayer adopté
	# avant tout — y compris avant la capture différée ci-dessous).
	_sync_preview_selection()
	# Tenue de fin authored (fin naturelle → le player retombe au repos :
	# re-fige la dernière frame, même pattern que l'établissement take).
	if _hold_end:
		_hold_end = false
		if not _authored_current.is_empty() and _take_player != null:
			var _lib := _authored_lib()
			var _end: Animation = _lib.get_animation(StringName(_authored_current)) if _lib != null else null
			if _end != null:
				var _tgt := StringName("authored/" + _authored_current)
				_take_player.play(_tgt)
				_take_player.pause()
				_take_player.seek(_end.length, true)
				print("[AnimCreator] authored %s held @ end %.3fs" % [_authored_current, _end.length])
	# Capture base différée (bouton Set-as-base : la take est pausée, pose
	# gelée exacte — sinon le travail courant). Handles recalés sur la take
	# (mains/pieds/hanches/genoux → articulations take) pour une capture
	# INVISIBLE : après décharge, l'IK reproduit la pose à l'identique, les
	# cubes repartent de zéro visuel avec leurs deltas intacts.
	if _pending_base:
		_pending_base = false
		# Depuis un preview (take ou authored, B2) : clear d'abord (ancienne
		# base en statics polluerait), puis live = pose pure du player.
		if _take_driving():
			_apply_override_clear()
		_snap_handles_to_live()
		# Goal rig-follow ré-ancré sur la pose capturée (handle sur l'os,
		# rig immobile) : goal == rig → zéro chasse post-capture, la pose
		# reproduite est la take à l'identique (pas de re-solve dérivé).
		var _rigc := get_node_or_null("RigRoot") as Node3D
		if _hips != null and _rigc != null:
			_hips_goal_off = _hips.global_position - _rigc.global_position
		# Côtés de pli réels (pôles take-aware) — lit le live intact (take
		# mixer ou overrides travail : le clear n'a lieu qu'au-dessus, et
		# seulement depuis une take où le live est la take pure).
		_capture_pole_dirs()
		_capture_live_base()
		_derive_base_refs()
		_write_base_statics()
		# Cubes à zéro (la base absorbe le visuel + deltas — sinon les deltas
		# persistants s'appliqueraient deux fois). Positions intactes.
		for limb in LIMB_ORDER:
			if _handles.has(limb):
				(_handles[limb] as Node3D).global_rotation = Vector3.ZERO
				_handle_rest_rot[limb] = Quaternion()
				if _proxy.has(limb):
					(_proxy[limb] as Node3D).global_position = (_handles[limb] as Node3D).global_position
		for n in [_torso, _head, _hips]:
			if n != null:
				(n as Node3D).global_rotation = Vector3.ZERO
		_torso_rest_rot = Quaternion()
		_head_rest_rot = Quaternion()
		_hips_rest_rot = Quaternion()
		_unload_take()
		# Miroir take retombé APRÈS capture+décharge : le setter early-return
		# (_take_want=false) — aucun seek.
		take_playing = false
		print("[AnimCreator] base = %s" % _base_name)
	# Règle unique (25/09 : workflow keyframe) — une take chargée = solveurs
	# + writers effacés : solves customs et writers skippés, rien ne touche
	# la take affichée.
	var driven: bool = _take_driving()
	if driven:
		return
	# Constraints next: bassin résolu d'abord (dos + jambes partent de là),
	# puis colonne (les bras composent leur racine depuis la colonne RÉSOLUE
	# même frame — REV 23, zéro lecture live), puis auto-poles, puis le rig
	# vers le handle hanches.
	_solve_hips()
	_apply_spine()
	_update_auto_poles()
	if _hips != null:
		var rig := get_node_or_null("RigRoot") as Node3D
		if rig != null:
			var goal: Vector3 = _hips.global_position - _hips_goal_off
			var rd: Vector3 = goal - rig.global_position
			rig.global_position = goal if rd.length() <= step else rig.global_position + rd.normalized() * step
	if _label == null or _skeleton == null:
		return
	# Custom solves (same frame, pre-pipeline — stateless analytic, remplit
	# les dicts + écrit upper/middle ; wrist/ankle writers consomment le
	# _solve_pos frais).
	for limb in LIMB_ORDER:
		if LEG_BONES.has(limb):
			_solve_leg(limb)
		else:
			_solve_arm(limb)
	# Wrist + ankle writes (même frame) : trace/label only read below.
	_apply_stored_wrist()
	_apply_stored_ankle()
	# Follow (25/09 : les cubes restent sur les os quand le corps bouge —
	# rotation authored intacte, seule la position est réécrite). Si l'humain
	# a déplacé le cube (éditeur live), on adopte son placement : nouvel
	# offset = pos − os, au lieu de l'écraser.
	if _spine_solved_pos.has(&"UpperChest"):
		var uw: Vector3 = _spine_solved_pos[&"UpperChest"]
		if not _follow_init or _torso.global_position.distance_to(_torso_last_follow) > 0.001:
			_torso_follow_off = _torso.global_position - uw
		_torso.global_position = uw + _torso_follow_off
		_torso_last_follow = _torso.global_position
	if _spine_solved_pos.has(&"Head"):
		var hw: Vector3 = _spine_solved_pos[&"Head"]
		if not _follow_init or _head.global_position.distance_to(_head_last_follow) > 0.001:
			_head_follow_off = _head.global_position - hw
		_head.global_position = hw + _head_follow_off
		_head_last_follow = _head.global_position
	_follow_init = true
	var event_limb := &""
	for limb in LIMB_ORDER:
		var f := _limb_flag(limb)
		if f != String(_flag.get(limb, "ok")):
			_flag[limb] = f
			event_limb = limb
			break
	if show_label:
		_write_label()
	elif _label != null and not _label_cleared:
		_label.text = "AnimCreator: trace in Output (show_label to restore overlay)"
		_label_cleared = true
	if trace_log:
		_trace_elapsed += delta
		_trace_accum += delta
		if event_limb != &"":
			_print_trace(true, String(event_limb))
			_trace_accum = 0.0
			_trace_key = _trace_signature()
		elif _trace_accum >= TRACE_MIN_INTERVAL:
			var key := _trace_signature()
			if key != _trace_key:
				_trace_key = key
				_trace_accum = 0.0
				_print_trace(false, "")


## Change signature: hips offset (mm) + per limb handle pos (mm) / handle
## rot (deg) / pole pos (mm), rounded to ints. Idle scene = identical key =
## silence (answers the log-spam report 25/09).
func _trace_signature() -> Array:
	var key: Array = []
	key.append(int(round((_hips.global_position - _hips_rest).length() * 1000.0)) if _hips != null else 0)
	if _hips != null:
		var he: Vector3 = _hips.global_rotation * 180.0 / PI
		key.append(int(round(he.x)))
		key.append(int(round(he.y)))
		key.append(int(round(he.z)))
	for limb in LIMB_ORDER:
		var h: Node3D = _handles.get(limb)
		var p: Node3D = _poles.get(limb)
		if h != null:
			key.append(int(round(h.global_position.x * 1000.0)))
			key.append(int(round(h.global_position.y * 1000.0)))
			key.append(int(round(h.global_position.z * 1000.0)))
			var e: Vector3 = h.global_rotation * 180.0 / PI
			key.append(int(round(e.x)))
			key.append(int(round(e.y)))
			key.append(int(round(e.z)))
		if p != null:
			key.append(int(round(p.global_position.x * 1000.0)))
			key.append(int(round(p.global_position.y * 1000.0)))
			key.append(int(round(p.global_position.z * 1000.0)))
		# Settled metrics (0.1mm / 0.01 / 1deg / mm): prints the post-move
		# solve once after the handles stop, then silence. Upper-bone euler
		# included (25/09 : le roll de cuisse est invisible à err/dot/flex/bow
		# — sans ça le log dit « ok » pendant que la fesse est inversée).
		key.append(int(round(float(_err.get(limb, 0.0)) * 10000.0)))
		key.append(int(round(float(_dot.get(limb, 0.0)) * 100.0)))
		key.append(int(round(float(_flex.get(limb, 0.0)))))
		key.append(int(round(float(_bow.get(limb, 0.0)) * 1000.0)))
		if _solve_upper.has(limb):
			var uq: Quaternion = _solve_upper[limb]
			var ue: Vector3 = uq.get_euler() * 180.0 / PI
			key.append(int(round(ue.x)))
			key.append(int(round(ue.y)))
			key.append(int(round(ue.z)))
	# Torso/head handle ROTATIONS only (translations ignored by design —
	# tracking them would log moves with zero effect).
	for n in [_torso, _head]:
		if n != null:
			var te: Vector3 = (n as Node3D).global_rotation * 180.0 / PI
			key.append(int(round(te.x)))
			key.append(int(round(te.y)))
			key.append(int(round(te.z)))
	# Knee handle POSITIONS (c'est la position qui pilote — rot ignorée).
	for leg in LEG_BONES:
		if _knee.has(leg):
			var kp: Vector3 = (_knee[leg] as Node3D).global_position
			key.append(int(round(kp.x * 1000.0)))
			key.append(int(round(kp.y * 1000.0)))
			key.append(int(round(kp.z * 1000.0)))
	return key


## Joint state flag shared by overlay + trace: bow sign ONLY, with a magnitude
## gate. Rationale (probes 25/09): under pinned-plane TwoBone the elbow cannot
## leave the plane, so dot-perpendicularity (elbow straight below root while
## the pole sits behind — the natural hang) is benign; the old dot<0 guard
## false-fired on every deep fold (attack pose: dot −0.20 with elbow correctly
## 154 mm behind). Crossing to the wrong side (bow<0) is the one real
## inversion — gated at −15 mm because a quasi-straight limb has no bend
## direction and its bow sign is millimeter noise (measured ±13 mm flips
## firing EVENTs on flex-16 legs).
func _limb_flag(limb: StringName) -> String:
	if float(_bow.get(limb, 0.0)) < -0.015 and float(_flex.get(limb, 0.0)) > 20.0:
		return "INV"
	return "ok"


func _write_label() -> void:
	_label_cleared = false
	var lines := PackedStringArray()
	for limb in LIMB_ORDER:
		var joint: String = (LIMB_NODES[limb] as Dictionary)["joint"]
		var flex := float(_flex[limb])
		var fwarn := " OVERFLEX" if flex > FLEX_WARN else ""
		lines.append("%s err=%.1fmm %s=%s (dot %.2f) flex=%.0f%s dist=%.0fcm" % [String(limb), float(_err[limb]) * 1000.0, joint, _limb_flag(limb), float(_dot[limb]), flex, fwarn, float(_prox[limb]) * 100.0])
	lines.append(" custom analytic 4 limbs | wrist %s ankle %s torso %s head %s | body +%.0fcm | gizmo: 9 clickable handles" % ["on" if wrist_copy else "off", "on" if ankle_copy else "off", "on" if torso_copy else "off", "on" if head_copy else "off", (_hips.global_position - _hips_rest).length() * 100.0 if _hips != null else 0.0])
	_label.text = "\n".join(lines)


## One pasteable trace line: handle pos + euler + pole pos + END-BONE euler
## (in-signal stored — the visible bone orientation) + solver metrics.
## EVENT lines fire immediately on flag transitions (the flip moments).
func _print_trace(is_event: bool, event_limb: String) -> void:
	var parts := PackedStringArray()
	parts.append("hips=+%.0fcm" % ((_hips.global_position - _hips_rest).length() * 1000.0 / 10.0 if _hips != null else 0.0))
	if _hips != null:
		var hre: Vector3 = _hips.global_rotation * 180.0 / PI
		parts.append("hipsrot r=(%.0f,%.0f,%.0f)" % [roundf(hre.x), roundf(hre.y), roundf(hre.z)])
	for limb in LIMB_ORDER:
		var h: Node3D = _handles.get(limb)
		var p: Node3D = _poles.get(limb)
		var hp := Vector3.ZERO
		var he := Vector3.ZERO
		var pp := Vector3.ZERO
		if h != null:
			hp = h.global_position
			var e: Vector3 = h.global_rotation * 180.0 / PI
			he = Vector3(roundf(e.x) + 0.0, roundf(e.y) + 0.0, roundf(e.z) + 0.0)
		if p != null:
			pp = p.global_position
		var be := Vector3.ZERO
		if _solve_end.has(limb):
			var q: Quaternion = _solve_end[limb]
			var eb: Vector3 = q.get_euler() * 180.0 / PI
			be = Vector3(roundf(eb.x) + 0.0, roundf(eb.y) + 0.0, roundf(eb.z) + 0.0)
		var ue := Vector3.ZERO
		if _solve_upper.has(limb):
			var uq: Quaternion = _solve_upper[limb]
			var ub: Vector3 = uq.get_euler() * 180.0 / PI
			ue = Vector3(roundf(ub.x) + 0.0, roundf(ub.y) + 0.0, roundf(ub.z) + 0.0)
		parts.append("%s h=(%.2f,%.2f,%.2f) r=(%.0f,%.0f,%.0f) bone=(%.0f,%.0f,%.0f) ubone=(%.0f,%.0f,%.0f) pole=(%.2f,%.2f,%.2f) err=%.1f dot=%.2f flex=%.0f bow=%.0f %s" % [String(limb), hp.x, hp.y, hp.z, he.x, he.y, he.z, be.x, be.y, be.z, ue.x, ue.y, ue.z, pp.x, pp.y, pp.z, float(_err.get(limb, -1.0)) * 1000.0, float(_dot.get(limb, 0.0)), float(_flex.get(limb, 0.0)), float(_bow.get(limb, 0.0)) * 1000.0, _limb_flag(limb)])
	for n in [&"torso", &"head"]:
		var nd: Node3D = _torso if n == &"torso" else _head
		if nd != null:
			var ne: Vector3 = nd.global_rotation * 180.0 / PI
			parts.append("%s r=(%.0f,%.0f,%.0f)" % [String(n), roundf(ne.x), roundf(ne.y), roundf(ne.z)])
	for leg in LEG_BONES:
		if _knee.has(leg):
			var kp: Vector3 = (_knee[leg] as Node3D).global_position
			var side_tag := "L" if String(leg).begins_with("Left") else "R"
			parts.append("knee%s=(%.2f,%.2f,%.2f)" % [side_tag, kp.x, kp.y, kp.z])
	var tag := "EVENT %s" % event_limb if is_event else "snap"
	print("[AnimCreator %s t=%.1f] %s" % [tag, _trace_elapsed, " | ".join(parts)])


## Re-snaps user handles to rest (Reset button). ATOMIC (log humain 25/09 :
## reset pendant hips baissé plaçait les handles 21 cm trop bas — to_global
## dans le frame déplacé — d'où le « reset 2x » : le 1er posait faux, le 2e
## corrigeait une fois le rig remonté). Ordre : 1) hips au repos, 2) rig
## snappé (pas de slew), 3) handles placés dans le frame corrigé, 4) proxies
## snappés sur les handles (pas de chase — le slew ne sert qu'aux drags).
## Auto-poles need no reset (recomputed every frame).
func reset_handles() -> void:
	if _skeleton == null or _handles.is_empty():
		push_warning("[AnimCreator] reset: rig not built yet")
		return
	if _hips != null:
		_hips.global_position = _hips_rest
		_hips.global_rotation = Vector3.ZERO
		_hips_rest_rot = Quaternion()
		var rig := get_node_or_null("RigRoot") as Node3D
		if rig != null:
			rig.global_position = _hips.global_position - _hips_rest
			_hips_goal_off = _hips.global_position - rig.global_position
	for limb in LIMB_ORDER:
		(_handles[limb] as Node3D).global_position = _skeleton.to_global(_rest[limb] as Vector3)
		(_handles[limb] as Node3D).global_rotation = Vector3.ZERO
		# Zero-point follows the reset (else a saved rotated handle would
		# leave a stale rest-rot and offset the wrist after reset).
		_handle_rest_rot[limb] = Quaternion()
		if _proxy.has(limb):
			(_proxy[limb] as Node3D).global_position = (_handles[limb] as Node3D).global_position
	# Torso/head handles: free authoring nodes — back to scene rest pos/rot.
	if _torso != null:
		_torso.global_position = _torso_rest_pos
		_torso.global_rotation = Vector3.ZERO
		_torso_rest_rot = Quaternion()
	if _head != null:
		_head.global_position = _head_rest_pos
		_head.global_rotation = Vector3.ZERO
		_head_rest_rot = Quaternion()
	for leg in LEG_BONES:
		if _knee.has(leg):
			(_knee[leg] as Node3D).global_position = _knee_rest_pos.get(leg, (_knee[leg] as Node3D).global_position)
			(_knee[leg] as Node3D).global_rotation = Vector3.ZERO
	# Stale-snapshot pop (log humain 25/09 : reset posé = 1 frame EVENT err 335
	# bow −99 — les writers rejouaient le snapshot d'avant-reset pendant une
	# frame). Clear overrides + snapshots (les writers skippent sur snapshot
	# vide, les signaux remplissent dès le prochain solve frais).
	_apply_override_clear()
	_solve_pos.clear()
	_solve_fore.clear()
	_solve_end.clear()
	_solve_upper.clear()
	_solve_middle.clear()
	_spine_solved_pos.clear()
	_spine_solved_quat.clear()
	print("[AnimCreator] handles reset")
	if trace_log:
		_print_trace(false, "")


## Validator seam (mirrors the spike — future bake guard). tracking_error /
## reach_of take any limb key (arms + legs); arms keep their named helpers.
func hand_rest_local(side: StringName) -> Vector3:
	return _rest.get(side, Vector3.ZERO)


func reach_of(side: StringName) -> float:
	return float(_reach.get(side, 0.5))


func set_hand_target(side: StringName, skeleton_local_pos: Vector3) -> void:
	if _handles.has(side) and _skeleton != null:
		(_handles[side] as Node3D).global_position = _skeleton.to_global(skeleton_local_pos)


func tracking_error(side: StringName) -> float:
	return float(_err.get(side, -1.0))


func elbow_dot(side: StringName) -> float:
	return float(_dot.get(side, 0.0))


func elbow_flexion(side: StringName) -> float:
	return float(_flex.get(side, 0.0))


func hand_shoulder_dist(side: StringName) -> float:
	return float(_prox.get(side, 0.0))


## Leg seam (same metrics, keyed by leg limb — future bake guard).
func set_foot_target(limb: StringName, skeleton_local_pos: Vector3) -> void:
	if _handles.has(limb) and _skeleton != null:
		(_handles[limb] as Node3D).global_position = _skeleton.to_global(skeleton_local_pos)


func knee_dot(limb: StringName) -> float:
	return float(_dot.get(limb, 0.0))


func knee_flexion(limb: StringName) -> float:
	return float(_flex.get(limb, 0.0))


func foot_hip_dist(limb: StringName) -> float:
	return float(_prox.get(limb, 0.0))


## Signed joint bow in mm along the pole side (negative = backward bend).
func bend_of(limb: StringName) -> float:
	return float(_bow.get(limb, 0.0))


## World orientation of the hand bone (step 2 gate: follow angle).
func hand_bone_quat(side: StringName) -> Quaternion:
	if _skeleton == null:
		return Quaternion()
	var bones: Dictionary = ARM_BONES.get(side, {})
	if bones.is_empty():
		return Quaternion()
	var hand_idx := _skeleton.find_bone(bones["end"])
	if hand_idx == -1:
		return Quaternion()
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(hand_idx)).basis.get_rotation_quaternion()


## World orientation of the foot bone, IN-SIGNAL stored (trace bone= column).
## Outside-signal live reads show rest for deterministic solves (pipeline
## lesson 25/09) — this seam returns the staged solve like the metrics do.
func foot_bone_quat(limb: StringName) -> Quaternion:
	return _solve_end.get(limb, Quaternion())


## World orientation of the upper bone (thigh / upper arm), IN-SIGNAL stored.
## Hip-fold + thigh-roll diagnosis (buttock collapse report 25/09).
func upper_bone_quat(limb: StringName) -> Quaternion:
	return _solve_upper.get(limb, Quaternion())


## World orientation of the middle bone (shin / forearm), IN-SIGNAL stored.
func middle_bone_quat(limb: StringName) -> Quaternion:
	return _solve_middle.get(limb, Quaternion())
