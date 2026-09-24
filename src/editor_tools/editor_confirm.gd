class_name EditorConfirm
extends RefCounted

## One-shot Godot-editor confirmation for @tool scripts (never in game — it
## needs EditorInterface): a modal ConfirmationDialog with a text/diff body.
## The caller owns the semantics: [param on_confirm] runs on Confirmer,
## nothing on Annuler. Single instance: passing the previous dialog frees it.
## Home: src/editor_tools/ (Godot-editor @tool helpers — not src/editors/,
## which is the in-game maker, nor src/cli_tools/, which is headless CLI).
## Usage from a tool:
##   _dlg = EditorConfirm.ask("Overwrite moveset entry?", text, "Overwrite", _on_ok.bind(params), _dlg)
static func ask(title: String, text: String, ok_label: String, on_confirm: Callable, replace: Window = null) -> ConfirmationDialog:
	if not Engine.is_editor_hint():
		push_warning("[EditorConfirm] no editor interface (headless: no-op)")
		return null
	if is_instance_valid(replace):
		replace.queue_free()
	var dlg := ConfirmationDialog.new()
	dlg.title = title
	dlg.dialog_text = text
	dlg.ok_button_text = ok_label
	dlg.cancel_button_text = "Cancel"
	dlg.min_size = Vector2i(460, 0)
	dlg.confirmed.connect(_run_and_free.bind(dlg, on_confirm))
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()
	return dlg


## Confirmed path: runs the caller's callback, then frees the dialog.
static func _run_and_free(dlg: ConfirmationDialog, on_confirm: Callable) -> void:
	on_confirm.call()
	if is_instance_valid(dlg):
		dlg.queue_free()
