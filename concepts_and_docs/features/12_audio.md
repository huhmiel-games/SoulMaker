# 12 — Audio (neutral spec — pillar vaulted)

> The **complete** audio design, described phase-neutrally. Everything here is currently in the vault (ADR-014) — the spec exists so that when audio returns the design is ready. Status lives in `features.md`.

## Audio system / mixer (buses)

**Goal** — a small, predictable mixing architecture every world inherits.
**Behaviors** — named buses: Master / Ambience / SFX / Music / UI; per-bus volume presets surfaced in Options (currently an inert shell); buses feed the master; ducking rules (music ducks under UI? SFX never ducked).
**Parameters / bounds** — bus list fixed; volume sliders bounded 0-100%.
**Data / JSON** — settings file (volumes).
**Interactions** — Options (`11`), every other audio feature.
**Edge cases** — volume fade transitions when changing buses.
**Sources** — ADR-014, screens Options.

## Positional audio (audience)

**Goal** — 3D-placed sounds: hits, dodges, footsteps, torches, ambiences.
**Behaviors** — `AudioStreamPlayer3D` per sound source; characters own their players (per-character implementation reacting to relay signals keeps anims generic); environmental emitters in catalog pieces (torch crackle, fireplace).
**Parameters / bounds** — max polyphony; distance/attenuation curves.
**Interactions** — `01` impact chain, `02` animation callbacks → relay → per-character player.
**Edge cases** — many torches (polyphony budget), occlusion.
**Sources** — idea.txt 1309-1327, ADR-014.

## Music — data-driven ("music as data")

**Goal** — every world can have its own soundtrack **without shipping audio files**: the music *is* data.
**Behaviors** — a song = a data format (notes/instruments/patterns) composed in a **tracker-style music editor** (proposed); the engine **pre-renders** each song to audio (WAV) once at load/import, then plays the WAV in a loop (CPU near-zero, no realtime synth cost in GDScript); crossfade between tracks (explore / combat / boss).
**Parameters / bounds** — data size tiny (few KB), pre-render cached with content-keyed hash (like impostors); instrument set from bounded presets.
**Data / JSON** — song data format + score as data; validated.
**Interactions** — world data (per-world tracks), `14` sharing (music rides the world file!), `13` (boss intro sting).
**Edge cases** — pre-render time at first load on low-end machines; missing track → silence (no error).
**Open questions** — tracker editor seat (post-V1); format vs MIDI-vs-custom; whether the render cache ships or regenerates.
**Sources** — decision 12/09 (music-as-data idea retained), ADR-014.

## SFX — impact & step (material-based)

**Goal** — the punch: sound on the exact contact frame, per material.
**Behaviors** — impact SFX fires on first impact image from **global anim callbacks** implemented per character (heavy vs light steps); material mapping (metal clong / flesh thud / stone / wood); footsteps heavy-vs-light per character; weapon whoosh optional.
**Parameters / bounds** — material→sound mapping bounded; latency must be zero-ish relative to impact.
**Data / JSON** — per-char sound config (step style), per-weapon material.
**Interactions** — `01` impact chain (hitstop + shake + VFX + SFX stack), `02` anim callbacks.
**Edge cases** — multiple simultaneous impacts (prioritize nearest/loudest).
**Sources** — idea.txt 2004, 2022, 1320-1326.

## Music beds (explore / combat / boss)

**Goal** — the souls audio arc: calm exploration, tense combat, boss pressure.
**Behaviors** — per-zone music bed; combat layer crossfades in during aggro; boss layer swaps on boss-level aggro (`11` boss bar trigger); all crossfaded on the Music bus.
**Parameters / bounds** — transition length ~1-2s.
**Data / JSON** — world music assignments.
**Interactions** — `05` enemy/boss state.
**Sources** — music-as-data decision.

## Ambience

**Goal** — zone atmosphere: wind, dripping, distant noise.
**Behaviors** — per-map/zone ambiance loop on the Ambience bus, fades between zones at sockets.
**Parameters / bounds** — preset list.
**Data / JSON** — per-map ambiance selection.
**Interactions** — `06` ambiance presets share the same concept.
**Sources** — screens Options (ambiance slider).

## UI sounds

**Goal** — menu/ticks/confirm on the UI bus.
**Behaviors** — short stings for confirm/cancel/tick/error.
**Sources** — screens Options (UI slider).

## Audio editor (vault)

**Goal** — creators compose their world's music/SFX placements.
**Behaviors** — tracker-style editor for songs (music-as-data) + SFX placement tooling in map editor; disputed scope — vaulted with the pillar.
**Interactions** — `09` editors.
**Sources** — decision 12/09.

## Catalog audio category (vault)

**Goal** — community-supplied "sounds" enter the catalog like meshes.
**Behaviors** — ADR-010 extension: `category: audio`, manifest bounds (duration, format), validation via headless listen; feeds SFX material maps.
**Data / JSON** — manifest entry + bounds.
**Interactions** — `10` catalog.
**Sources** — ADR-014, `10_catalog.md`.

---

## Vault posture

All items in this file are **vaulted by decision (ADR-014)**. When audio re-enters scope:
1. Decide music-as-data tracker vs shipping samples.
2. Extend catalog (audio category) + Options becomes live.
3. Sequence in roadmap (see `roadmap.md` P2 game-feel note).