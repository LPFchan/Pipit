#!/usr/bin/env python3
"""
Generate a placeholder Uguisu fob GLB for Pipit (Agent 6).
Dimensions approximate: enclosure ~50×35×12 mm, button ~5.2×5.2 mm, LED mesh for runtime control.
Mesh names: body (or root), button (depressible), led_rgb (emissive LED target).
Output: uguisu_placeholder.glb
"""
import sys
from pathlib import Path

try:
    import trimesh
    import numpy as np
except ImportError:
    print("Run: pip install -r scripts/requirements-placeholder.txt", file=sys.stderr)
    sys.exit(1)

# Approximate dimensions in meters (glTF uses meters)
# Body: 50×35×12 mm → 0.05 x 0.035 x 0.012
BODY_EXTENTS = [0.05, 0.035, 0.012]
# Button on top face, centered, 5.2×5.2 mm, slightly proud
BUTTON_EXTENTS = [0.0052, 0.0052, 0.0015]
# LED: small quad/disc on front face, named led_rgb for runtime emissive
LED_RADIUS = 0.002
LED_HEIGHT = 0.0005

def make_body():
    box = trimesh.creation.box(extents=BODY_EXTENTS)
    box.name = "body"
    return box

def make_button():
    # Button sits on top of body (+Z). Center at (0, 0, BODY_EXTENTS[2]/2 + BUTTON_EXTENTS[2]/2)
    box = trimesh.creation.box(extents=BUTTON_EXTENTS)
    box.apply_translation([0, 0, BODY_EXTENTS[2] / 2 + BUTTON_EXTENTS[2] / 2])
    box.name = "button"
    return box

def make_led():
    # Small cylinder (disc) for LED, on front face (+Y) of body
    cyl = trimesh.creation.cylinder(radius=LED_RADIUS, height=LED_HEIGHT)
    cyl.apply_translation([0, BODY_EXTENTS[1] / 2 + LED_HEIGHT / 2, 0])
    cyl.name = "led_rgb"
    return cyl

def main():
    root = Path(__file__).resolve().parent.parent
    out_dir = root / "assets"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "uguisu_placeholder.glb"

    body = make_body()
    button = make_button()
    led = make_led()

    # Combine into one scene; glTF export will preserve mesh names when we export each as separate mesh
    scene = trimesh.Scene()
    scene.add_geometry(body, node_name="body")
    scene.add_geometry(button, node_name="button")
    scene.add_geometry(led, node_name="led_rgb")

    # Export as GLB (trimesh exports all geometry; mesh names come from node names / geometry names)
    # Trimesh 4.x export_scene to glb
    scene.export(str(out_path), file_type="glb")
    print(f"Wrote {out_path}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
