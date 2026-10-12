bl_info = {
    "name": "SoulMaker Part Export",
    "description": "Export the active mesh (+ armature) as a SoulMaker asset: auto-detected folder/name, textures deduplicated into shared/ with shared/ URIs.",
    "author": "SoulMaker",
    "version": (1, 1, 0),
    "blender": (4, 3, 0),
    "category": "Import-Export",
}
# Install once: Edit > Preferences > Add-ons > Install from Disk > this file.
# Use: select a mesh, 3D Viewport > sidebar (N) > SoulMaker > Export part.
# Gender comes from the .blend filename, folder + file stem from the object
# name (previewed before OK, still editable). Visibility is restored after.

import bpy
import hashlib
import json
import os
import re
from bpy.props import EnumProperty, StringProperty


# --------------------------------------------------------------------------
# Export settings (frozen from the known-good male eyes export, 12/10).
# Only these kwargs are passed (stable across Blender versions); everything
# else stays on Blender defaults. Tweak here if Godot-side pins complain.
EXPORT_KWARGS = {
    "export_format": "GLTF_SEPARATE",
    "use_selection": True,
    "export_apply": False,  # keep the Armature modifier live (skinning!)
    "export_yup": True,
    "export_skins": True,
    "export_materials": "EXPORT",
    "export_texcoords": True,
    "export_normals": True,
}

# Tree roots relative to the .blend folder (blends live in meshes/blender/).
TREE_ROOTS = {
    "parts": "../characters/parts/",
    "outfits": "../outfits/",
}

SLOT_ITEMS = [
    ("eyes", "eyes (parts)", ""),
    ("eyebrows", "eyebrows (parts)", ""),
    ("eyelashes", "eyelashes (parts)", ""),
    ("hairs", "hairs (parts)", ""),
    ("beards", "beards (parts)", ""),
    ("bodies", "bodies (outfits)", ""),
    ("hands", "hands = Arms (outfits)", ""),
    ("legs", "legs (outfits)", ""),
    ("feets", "feets (outfits)", ""),
    ("heads", "heads (outfits)", ""),
    ("accessories", "accessories (outfits)", ""),
]


def _detect_gender(blend_path):
    """female first: 'female' contains 'male'."""
    base = os.path.basename(blend_path).lower()
    if "female" in base:
        return "female"
    if "male" in base:
        return "male"
    return ""


def _detect_target(obj_name):
    """(tree, slot) from the object name. Order matters: 'eyebrow' and
    'eyelashes' contain 'eye'; 'Hair_Beard' contains 'hair'."""
    nm = (obj_name or "").lower()
    if "beard" in nm:
        return ("parts", "beards")
    if "eyebrow" in nm:
        return ("parts", "eyebrows")
    if "eyelash" in nm:
        return ("parts", "eyelashes")
    if "hair" in nm:
        return ("parts", "hairs")
    if "body" in nm or "bodies" in nm:
        return ("outfits", "bodies")
    if "arms" in nm:
        return ("outfits", "hands")  # repo quirk: Arms live in hands/
    if "legs" in nm:
        return ("outfits", "legs")
    if "feet" in nm or "boots" in nm:
        return ("outfits", "feets")
    if "head" in nm or "hood" in nm:
        return ("outfits", "heads")
    if "gauntlet" in nm or "pauldron" in nm or "_acc" in nm:
        return ("outfits", "accessories")
    if "eye" in nm:
        return ("parts", "eyes")
    return ("", "")


def _sanitize_stem(name):
    """Strip Blender duplicate suffixes (Foo.001 -> Foo)."""
    return re.sub(r"\.\d+$", "", name or "")


def _target_path(root_dir, gender, slot, stem):
    return os.path.join(root_dir, gender, slot, stem + ".gltf")


def _sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


class SOULMAKER_OT_export_part(bpy.types.Operator):
    bl_idname = "soulmaker.export_part"
    bl_label = "Export part"
    bl_options = {"REGISTER"}

    tree: EnumProperty(name="Tree", items=[("parts", "parts", ""), ("outfits", "outfits", "")], default="parts")
    gender: EnumProperty(name="Gender", items=[("male", "male", ""), ("female", "female", "")], default="female")
    slot: EnumProperty(name="Slot", items=SLOT_ITEMS, default="eyes")
    filename: StringProperty(name="File name", default="")
    dest_dir: StringProperty(
        name="Tree root",
        description="Tree root (gender/slot below, shared/ beside). // = blend file folder",
        subtype="DIR_PATH",
        default="//../characters/parts/",
    )

    def invoke(self, context, event):
        obj = context.view_layer.objects.active
        if obj is not None and obj.type == "MESH":
            stem = _sanitize_stem(obj.name)
            if stem != obj.name:
                self.report({"WARNING"}, "Sanitized '%s' -> '%s'" % (obj.name, stem))
            self.filename = stem
            tree, slot = _detect_target(obj.name)
            if tree:
                self.tree = tree
            if slot:
                self.slot = slot
        g = _detect_gender(bpy.data.filepath)
        if g:
            self.gender = g
        roots = TREE_ROOTS.get(self.tree, TREE_ROOTS["parts"])
        self.dest_dir = "//" + roots if not roots.startswith("//") else roots
        return context.window_manager.invoke_props_dialog(self)

    def execute(self, context):
        obj = context.view_layer.objects.active
        if obj is None or obj.type != "MESH":
            self.report({"ERROR"}, "Active object must be a MESH")
            return {"CANCELLED"}
        arm = None
        for mod in obj.modifiers:
            if mod.type == "ARMATURE" and mod.object is not None:
                arm = mod.object
                break
        if arm is None:
            self.report({"ERROR"}, "No Armature modifier on '%s'" % obj.name)
            return {"CANCELLED"}

        root_dir = os.path.normpath(bpy.path.abspath(self.dest_dir))
        slot_dir = os.path.join(root_dir, self.gender, self.slot)
        shared_dir = os.path.join(root_dir, "shared")
        os.makedirs(slot_dir, exist_ok=True)
        os.makedirs(shared_dir, exist_ok=True)
        stem = _sanitize_stem(self.filename or obj.name)
        gltf_path = _target_path(root_dir, self.gender, self.slot, stem)

        # Isolate armature + object (object-level flags only, restored below).
        saved = {}
        for o in context.view_layer.objects:
            saved[o.name] = o.hide_viewport
            o.hide_viewport = o.name not in (obj.name, arm.name)
        try:
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            arm.select_set(True)
            context.view_layer.objects.active = obj
            bpy.ops.export_scene.gltf(filepath=gltf_path, **EXPORT_KWARGS)
        finally:
            for o in context.view_layer.objects:
                if o.name in saved:
                    try:
                        o.hide_viewport = saved[o.name]
                    except ReferenceError:
                        pass  # object gone mid-export, nothing to restore
            obj.select_set(True)
            context.view_layer.objects.active = obj

        # Post-pass: move images to shared/ (dedupe by hash), rewrite URIs.
        moved, reused, warned = self._share_images(gltf_path, shared_dir)
        self.report({"INFO"}, "Exported %s (+%d shared, %d reused%s)" % (
            os.path.basename(gltf_path), moved, reused,
            ", %d renamed (name clash)" % warned if warned else ""))
        return {"FINISHED"}

    def _share_images(self, gltf_path, shared_dir):
        with open(gltf_path, "r", encoding="utf-8") as f:
            text = f.read()
        try:
            doc = json.loads(text)
        except ValueError:
            self.report({"ERROR"}, "Cannot parse exported JSON, URIs left local")
            return (0, 0, 0)
        slot_dir = os.path.dirname(gltf_path)
        moved = reused = warned = 0
        for img in doc.get("images", []):
            uri = img.get("uri")
            if not uri or uri.startswith("data:") or uri.startswith("../../shared/"):
                continue  # embedded, Buffalo-style, or already shared
            src = os.path.normpath(os.path.join(slot_dir, uri))
            if not os.path.isfile(src):
                self.report({"WARNING"}, "Image missing on disk: %s" % uri)
                continue
            digest = _sha1(src)
            base = os.path.basename(uri)
            dst = os.path.join(shared_dir, base)
            if os.path.isfile(dst):
                if _sha1(dst) == digest:
                    pass  # identical already there
                else:
                    stem, ext = os.path.splitext(base)
                    k = 1
                    while True:
                        cand = "%s_%d%s" % (stem, k, ext)
                        cpath = os.path.join(shared_dir, cand)
                        if not os.path.isfile(cpath):
                            break
                        if _sha1(cpath) == digest:
                            break
                        k += 1
                    dst = cpath
                    warned += 1
                    self.report({"WARNING"}, "Name clash in shared/, using %s" % cand)
                    with open(src, "rb") as fi, open(dst, "wb") as fo:
                        fo.write(fi.read())
            else:
                with open(src, "rb") as fi, open(dst, "wb") as fo:
                    fo.write(fi.read())
                moved += 1
            new_uri = "../../shared/" + os.path.basename(dst)
            if new_uri != uri:
                text = re.sub(r'"uri"\s*:\s*"' + re.escape(uri) + '"',
                              '"uri": "%s"' % new_uri, text)
            else:
                reused += 1
            try:
                os.remove(src)
            except OSError:
                pass
        with open(gltf_path, "w", encoding="utf-8") as f:
            f.write(text)
        return (moved, reused, warned)


class SOULMAKER_PT_panel(bpy.types.Panel):
    bl_label = "SoulMaker"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "SoulMaker"

    def draw(self, context):
        layout = self.layout
        obj = context.view_layer.objects.active
        if obj is not None and obj.type == "MESH":
            tree, slot = _detect_target(obj.name)
            g = _detect_gender(bpy.data.filepath) or "?"
            stem = _sanitize_stem(obj.name)
            if tree and slot:
                layout.label(text="> %s/%s/%s/%s.gltf" % (tree, g, slot, stem))
            else:
                layout.label(text="> no match, set manually")
        layout.operator("soulmaker.export_part", text="Export part")


def register():
    bpy.utils.register_class(SOULMAKER_OT_export_part)
    bpy.utils.register_class(SOULMAKER_PT_panel)


def unregister():
    bpy.utils.unregister_class(SOULMAKER_PT_panel)
    bpy.utils.unregister_class(SOULMAKER_OT_export_part)


if __name__ == "__main__":
    register()
