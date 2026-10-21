"""Top-down map render of the generated world (from tests/server.spec.luau dumps).

Usage: python3 tools/render_map.py tests/out/map.json tests/out/heightmap.json out.png [x0 z0 x1 z1]
"""
import json
import sys

from PIL import Image, ImageDraw

HALF = 1952


def main():
    parts_path, height_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
    view = [float(v) for v in sys.argv[4:8]] if len(sys.argv) >= 8 else [-HALF, -HALF, HALF, HALF]
    x0, z0, x1, z1 = view
    size = 2000
    scale = size / max(x1 - x0, z1 - z0)
    W = int((x1 - x0) * scale)
    H = int((z1 - z0) * scale)
    img = Image.new("RGB", (W, H), (90, 140, 80))
    draw = ImageDraw.Draw(img)

    def px(x, z):
        return ((x - x0) * scale, (z - z0) * scale)

    # terrain
    rows = json.load(open(height_path))
    step = 16
    for ri, row in enumerate(rows):
        z = -HALF + ri * step
        for ci, cell in enumerate(row.split(" ")):
            x = -HALF + ci * step
            if x + step < x0 or x > x1 or z + step < z0 or z > z1:
                continue
            h, m = cell.split(":")
            h = float(h)
            if m == "Sa":
                base = (214, 196, 140)
            elif m == "Ro":
                base = (128, 124, 116)
            else:
                base = (88, 142, 76)
            shade = 1 + min(h, 80) / 110
            col = tuple(min(255, int(c * shade)) for c in base)
            a = px(x, z)
            b = px(x + step, z + step)
            draw.rectangle([a, b], fill=col)

    data = json.load(open(parts_path))
    parts = data["parts"]

    def top(p):
        return p["cf"][1] + p["size"][1] / 2

    parts.sort(key=top)
    for p in parts:
        sx, sy, sz = p["size"]
        cf = p["cf"]
        cx, cy, cz = cf[0], cf[1], cf[2]
        r = cf[3:12]
        # world = R * local; footprint corners in local XZ
        corners = []
        for lx, lz in ((-sx / 2, -sz / 2), (sx / 2, -sz / 2), (sx / 2, sz / 2), (-sx / 2, sz / 2)):
            wx = cx + r[0] * lx + r[2] * lz
            wz = cz + r[6] * lx + r[8] * lz
            corners.append(px(wx, wz))
        col = tuple(int(c * 255) for c in p["c"])
        draw.polygon(corners, fill=col)

    for cp in data["checkpoints"]:
        a = px(cp["x"], cp["z"])
        rr = 5
        draw.ellipse([a[0] - rr, a[1] - rr, a[0] + rr, a[1] + rr], outline=(255, 40, 200), width=2)
        draw.text((a[0] + 6, a[1] - 6), f'{cp["t"][0]}{cp["i"]}', fill=(255, 255, 255))
    img.save(out)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main()
