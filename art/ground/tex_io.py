"""Shared helper: write numpy images as PNG through Blender's image API (no extra libraries)."""
import os

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def save_png(path: str, img: np.ndarray) -> None:
    """img: (H, W, 3 or 4) floats 0..1, row 0 = top of the picture, values already sRGB-encoded
    for colour maps (byte images store what they are given, no colour conversion)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    h, w, c = img.shape
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :c] = img
    has_alpha = c == 4
    image = bpy.data.images.new("tmp_save", width=w, height=h, alpha=has_alpha)
    image.alpha_mode = "STRAIGHT"
    image.pixels.foreach_set(rgba[::-1].ravel())  # Blender stores the bottom row first.
    image.filepath_raw = path
    image.file_format = "PNG"
    # image.save() writes the bytes as they are; save_render() would apply the scene's view
    # transform (AgX) and shift every colour.
    image.save()
    bpy.data.images.remove(image)
