# Blender headless export for menu LOD.
# Usage:
# blender -b -P tools/blender/export_menu_lod.py -- --input "..." --output "..." --ratio 0.92 --weight-limit 8 --body-max 4096 --joint-max 2048

import argparse
import os
import sys

import bpy


def _parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []

    parser = argparse.ArgumentParser(description="Export menu LOD GLB")
    parser.add_argument("--input", required=True, help="Path to source GLB")
    parser.add_argument("--output", required=True, help="Path to output GLB")
    parser.add_argument("--ratio", type=float, default=0.92, help="Decimate ratio per mesh")
    parser.add_argument("--weight-limit", type=int, default=8, help="Max bone influences per vertex")
    parser.add_argument("--body-max", type=int, default=4096, help="Max dimension for body textures")
    parser.add_argument("--joint-max", type=int, default=2048, help="Max dimension for joints textures")
    return parser.parse_args(argv)


def _material_target_size(material_name: str, body_max: int, joint_max: int) -> int:
    name = material_name.lower()
    if "joint" in name:
        return joint_max
    return body_max


def _downscale_images(body_max: int, joint_max: int) -> None:
    image_targets = {}
    for material in bpy.data.materials:
        if material.node_tree is None:
            continue
        target = _material_target_size(material.name, body_max, joint_max)
        for node in material.node_tree.nodes:
            if node.type != "TEX_IMAGE" or node.image is None:
                continue
            image = node.image
            current = image_targets.get(image)
            image_targets[image] = target if current is None else min(current, target)

    for image, target in image_targets.items():
        width, height = image.size
        if width == 0 or height == 0:
            continue
        if max(width, height) <= target:
            continue
        scale = target / float(max(width, height))
        new_width = max(1, int(round(width * scale)))
        new_height = max(1, int(round(height * scale)))
        print("Downscale image", image.name, f"{width}x{height} -> {new_width}x{new_height}")
        image.scale(new_width, new_height)


def _apply_decimate_and_weights(decimate_ratio: float, weight_limit: int) -> None:
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="OBJECT")

        if decimate_ratio < 1.0:
            decimate = obj.modifiers.new(name="MenuLOD_Decimate", type="DECIMATE")
            decimate.ratio = decimate_ratio
            decimate.use_collapse_triangulate = True
            while obj.modifiers[0] != decimate:
                bpy.ops.object.modifier_move_up(modifier=decimate.name)
            bpy.ops.object.modifier_apply(modifier=decimate.name)

        if obj.vertex_groups and weight_limit > 0:
            bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
            bpy.ops.object.vertex_group_limit_total(limit=weight_limit)
            bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.001)
            bpy.ops.object.mode_set(mode="OBJECT")


def main() -> None:
    args = _parse_args()
    input_path = os.path.abspath(args.input)
    output_path = os.path.abspath(args.output)

    if not os.path.exists(input_path):
        raise FileNotFoundError(f"Input GLB not found: {input_path}")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    print("Import GLB:", input_path)
    bpy.ops.import_scene.gltf(filepath=input_path)

    print("Apply decimate and weight limits")
    _apply_decimate_and_weights(args.ratio, args.weight_limit)

    print("Downscale textures")
    _downscale_images(args.body_max, args.joint_max)

    print("Export GLB:", output_path)
    bpy.ops.export_scene.gltf(filepath=output_path, export_format="GLB")

    print("Done")


if __name__ == "__main__":
    main()
