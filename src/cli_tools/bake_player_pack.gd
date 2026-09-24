extends SceneTree

## Bakes the player pack (scenes/anim_lab/player_pack.res): the curated
## runtime library — same merge+filter as the lab, exported on demand via
## the lab's "Export player pack" button (or here, headless). The game mounts
## it directly when present and skips rebuilding from the .glb packs.
## Run: <godot> --headless --path . --script res://src/cli_tools/bake_player_pack.gd
const OUT_PACK := PlayerPackBaker.PLAYER_PACK_OUT


func _initialize() -> void:
	var err := PlayerPackBaker.bake_to(get_root(), OUT_PACK, "Pack")
	quit(0 if err == OK else 1)
