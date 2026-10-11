# 13 — Presentation & cinematics

> The "face-visible moments" — where video-game presentation lives. Everything here is currently **vaulted by decision (ADR-014)** — neutral spec keeps the design ready. Boss HP bar is NOT here (it's a HUD element, `11`). Status lives in `features.md`.

## Face-visible moments (framing rule)

**Goal** — the rule that lets the cheap 2D-face system carry the genre's key moments.
**Behaviors** — in normal gameplay the character is seen from behind ~90% of the time; front face is reserved for the few moments that must be seen: **boss intros, NPC dialogue, scripted deaths, cutscenes**. Cinematic framing avoids extreme close-ups; medium shots + dramatic lighting + hair/shadows cover the minimal facial rig.
**Parameters / bounds** — blend shapes budget kept (~5-10) precisely because the face is rarely seen.
**Data / JSON** — cinematic asset references.
**Interactions** — `02` face/blend system, `08` NPC dialogue (text-only speech, resolved 13/09/2026).
**Sources** — idea.txt 50-62, 455-463, 428.

## Cutscenes (camera + tight editing)

**Goal** — cinematic presentation at the breadcrumb moments without a full rig.
**Behaviors** — fixed face + light blend shapes + dramatic lighting + tight editing; camera timeline of shots (no interactive control); options: authored camera paths in-editor vs position/time-keyframes; sourced from dialogue events or boss triggers.
**Parameters / bounds** — shot duration, camera easing.
**Data / JSON** — cutscene timeline resource (shots: camera, duration, lighting, face pose).
**Interactions** — `08` events (trigger a cutscene), `06` camera/ambiance, `02` face.
**Edge cases** — skipping, player death mid-cutscene, low-end frame drops during cinematic.
**Open questions** — full cutscene editor (post-V1) vs data-only timelines.
**Sources** — idea.txt 56-62, 459-463, 108/497-500 (cutscenes as budgeted exception).

## Area name cards

**Goal** — the "Undead Burg" reveal: a styled world/area name fading in on entry.
**Behaviors** — a card (name + optional subtitle) fading in/out on zone entry; styled frame; **world-level configurable** (label, subtitle, art).
**Parameters / bounds** — one per zone entry or per socket; bounded duration.
**Data / JSON** — area card config on world/map.
**Interactions** — `06` transitions, `11` HUD/UI.
**Edge cases** — re-entry (re-show or suppress), first-run highlight.
**Sources** — decision 12/09 (vaulted), idea.txt (gaps).

## Boss intro / defeat presentation

**Goal** — the boss encounter's hero moment: name + health reveal + the signature gate.
**Behaviors** — on boss aggro: fog-gate seals the arena (the gate itself — `07` — is V1; what's vaulted is the cinematic layer: name card, camera drift, music sting) — HP bar already live via `11` boss bar; defeat: permanent "boss defeated" state (V1, `05`) + optional cinematic flourish (vaulted).
**Parameters / bounds** — duration, sting (music), camera movement bounded.
**Data / JSON** — boss config presentation fields (name, sting id, title art).
**Interactions** — `05` boss state, `11` boss bar, `07` fog gate triggers, `12` music.
**Edge cases** — player leaves arena mid-intro, retry loops (re-show).
**Sources** — idea.txt 50/455, decision 12/09 (ADR-014).

## Death presentation (scripted)

**Goal** — the classic death "camera" that turns failure into moment.
**Behaviors** — (post-V1 flourish) distinct from the V1 death/ respawn screen (`11`): a quasi-cutscene using the minimal face budget; default V1 = the death screen only.
**Data / JSON** — optional death cinematic ref in world.
**Interactions** — `11` death screen, `03` death rules.
**Sources** — idea.txt 50/455 (<scripted death>).

## Dialogue presentation (face + text)

**Goal** — NPC talk is a face-visible moment (speech resolved 13/09/2026).
**Behaviors** — **text-only speech** (no voice, no lip-sync): the dialogue box shows the `line` text, the NPC face stays still (talk loop dropped 10/10/2026 with the texture-face plan, `02`).
**Interactions** — `02` face anim, `08` dialogue.
**Open questions** — none (speech resolved 13/09/2026: text only).
**Sources** — idea.txt 72, 470, 797-811.

---

## Vault posture

Everything above is **vaulted (ADR-014)**. When presentation re-enters scope, the design resumes from this file; the V1-excluded items that remain are only `11` boss bar + `03` death screen + `07` fog gate (V1-safe already).