#!/usr/bin/env python3
"""
Generate a minimal placeholder Uguisu GLB using only Python stdlib.
Produces 3 named meshes: body, button, led_rgb (for Agent 6 contract).
"""
import json
import struct
import sys
from pathlib import Path

# Box vertices (x,y,z) in meters. One unit box [-0.5,0.5]^3, we scale per mesh.
# 8 vertices, 12 triangles (36 indices)
def unit_box_vertices():
    return [
        [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, 0.5, -0.5], [-0.5, 0.5, -0.5],
        [-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [0.5, 0.5, 0.5], [-0.5, 0.5, 0.5],
    ]

def unit_box_indices():
    return [
        0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
        0, 4, 5, 0, 5, 1, 2, 6, 7, 2, 7, 3,
        0, 3, 7, 0, 7, 4, 1, 5, 6, 1, 6, 2,
    ]

def scale_vertices(verts, sx, sy, sz):
    return [[v[0] * sx, v[1] * sy, v[2] * sz] for v in verts]

def flatten(verts):
    out = []
    for v in verts:
        out.extend(v)
    return out

def main():
    root = Path(__file__).resolve().parent.parent
    out_dir = root / "assets"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "uguisu_placeholder.glb"

    # Dimensions in meters (approx Uguisu: 50x35x12 mm body, 5.2mm button, small LED)
    body_v = scale_vertices(unit_box_vertices(), 0.025, 0.0175, 0.006)   # 50x35x12 mm
    button_v = scale_vertices(unit_box_vertices(), 0.0026, 0.0026, 0.00075)  # 5.2mm, on top
    for v in button_v:
        v[2] += 0.006 + 0.00075  # translate on top of body
    led_v = scale_vertices(unit_box_vertices(), 0.004, 0.004, 0.00025)  # small flat box for LED
    for v in led_v:
        v[1] += 0.0175 + 0.00025  # front face of body

    all_verts = body_v + button_v + led_v
    base = unit_box_indices()
    body_indices = [i for i in base]
    button_indices = [i + 8 for i in base]
    led_indices = [i + 16 for i in base]

    # Binary buffer: positions (24*3 floats = 72 floats = 288 bytes), then indices (36*3 = 108 uint16)
    positions = flatten(all_verts)
    buf_pos = bytearray()
    for f in positions:
        buf_pos += struct.pack("<f", f)
    buf_idx = bytearray()
    for i in body_indices + button_indices + led_indices:
        buf_idx += struct.pack("<H", i)
    pad = (4 - (len(buf_pos) % 4)) % 4
    buf_pos += bytes(pad)
    bin_buffer = buf_pos + buf_idx
    # Pad BIN to 4-byte alignment
    bin_pad = (4 - (len(bin_buffer) % 4)) % 4
    bin_buffer += bytes(bin_pad)

    # glTF 2.0 JSON (minimal)
    pos_byte_len = len(buf_pos)
    idx_byte_len = len(buf_idx)
    gltf = {
        "asset": {"version": "2.0", "generator": "Pipit placeholder script"},
        "scene": 0,
        "scenes": [{"nodes": [0, 1, 2]}],
        "nodes": [
            {"name": "body", "mesh": 0},
            {"name": "button", "mesh": 1},
            {"name": "led_rgb", "mesh": 2},
        ],
        "meshes": [
            {"name": "body", "primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "mode": 4}]},
            {"name": "button", "primitives": [{"attributes": {"POSITION": 0}, "indices": 2, "mode": 4}]},
            {"name": "led_rgb", "primitives": [{"attributes": {"POSITION": 0}, "indices": 3, "mode": 4}]},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 24, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5123, "count": 36, "type": "SCALAR"},
            {"bufferView": 2, "componentType": 5123, "count": 36, "type": "SCALAR"},
            {"bufferView": 3, "componentType": 5123, "count": 36, "type": "SCALAR"},
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": pos_byte_len, "target": 34962},
            {"buffer": 0, "byteOffset": pos_byte_len, "byteLength": idx_byte_len, "target": 34963},
            {"buffer": 0, "byteOffset": pos_byte_len, "byteLength": idx_byte_len, "target": 34963},
            {"buffer": 0, "byteOffset": pos_byte_len, "byteLength": idx_byte_len, "target": 34963},
        ],
        "buffers": [{"byteLength": len(bin_buffer)}],
    }
    # Fix: each mesh needs its own index range in the buffer. We have one shared position buffer
    # and three index ranges: body 0..107 (bytes 0..215), button 108..215 (bytes 216..431), led 216..323 (bytes 432..647)
    # So bufferViews for indices: [pos], [idx_body], [idx_button], [idx_led]
    # Byte offsets: pos 0, idx at pos_byte_len. But we concatenated body_indices, button_indices, led_indices - so
    # view1: offset pos_byte_len, length 216 (108 bytes * 2)
    # view2: offset pos_byte_len + 216, length 216
    # view3: offset pos_byte_len + 432, length 216
    gltf["bufferViews"] = [
        {"buffer": 0, "byteOffset": 0, "byteLength": pos_byte_len, "target": 34962},
        {"buffer": 0, "byteOffset": pos_byte_len, "byteLength": 216, "target": 34963},
        {"buffer": 0, "byteOffset": pos_byte_len + 216, "byteLength": 216, "target": 34963},
        {"buffer": 0, "byteOffset": pos_byte_len + 432, "byteLength": 216, "target": 34963},
    ]
    # accessor for indices: byteOffset in bufferView. Our bufferView 1 has indices 0..35 (body), but they're stored as 0..35 (vertex offset 0-7). So accessor 1 count 36, byteOffset 0. accessor 2 count 36, byteOffset 216 (first index of button in buffer = 108*2). Actually bufferView 2 starts at pos_byte_len+216 and has 108 bytes = 54 uint16 - we need 36 indices = 72 bytes. So each index list is 36*2 = 72 bytes.
    # So: body indices 72 bytes, button 72, led 72. Total 216. Good.
    gltf["bufferViews"] = [
        {"buffer": 0, "byteOffset": 0, "byteLength": pos_byte_len, "target": 34962},
        {"buffer": 0, "byteOffset": pos_byte_len, "byteLength": 72, "target": 34963},
        {"buffer": 0, "byteOffset": pos_byte_len + 72, "byteLength": 72, "target": 34963},
        {"buffer": 0, "byteOffset": pos_byte_len + 144, "byteLength": 72, "target": 34963},
    ]
    # Rebuild bin_buffer: pos (288 + pad), then 36*2 * 3 = 216 bytes indices
    buf_idx_body = struct.pack("<" + "H" * 36, *body_indices)
    buf_idx_button = struct.pack("<" + "H" * 36, *button_indices)
    buf_idx_led = struct.pack("<" + "H" * 36, *led_indices)
    bin_buffer = buf_pos + buf_idx_body + buf_idx_button + buf_idx_led
    bin_pad = (4 - (len(bin_buffer) % 4)) % 4
    bin_buffer += bytes(bin_pad)
    gltf["buffers"] = [{"byteLength": len(bin_buffer)}]

    json_str = json.dumps(gltf, separators=(",", ":"))
    json_bytes = json_str.encode("utf-8")
    json_pad = (4 - (len(json_bytes) % 4)) % 4
    json_bytes += b" " * json_pad

    # GLB: magic, version 2, total length; chunk0 (JSON), chunk1 (BIN)
    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_buffer)
    header = struct.pack("<III", 0x46546C67, 2, total_len)
    chunk0 = struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
    chunk1 = struct.pack("<II", len(bin_buffer), 0x004E4942) + bin_buffer

    with open(out_path, "wb") as f:
        f.write(header)
        f.write(chunk0)
        f.write(chunk1)
    print(f"Wrote {out_path}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
