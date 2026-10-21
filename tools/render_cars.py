"""Software renderer for car geometry dumped by tests/cars.spec.luau.

Usage: python3 tools/render_cars.py tests/out/cars.json tests/out/cars.png

Draws every car from a front 3/4 view and a rear 3/4 view with a z-buffer,
so body shapes can be reviewed without opening Roblox Studio.
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw


def block_mesh():
    v = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
    # index = x*4 + y*2 + z
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    tris = []
    for a, b, c, d in quads:
        tris += [(a, b, c), (a, c, d)]
    return v, tris


def wedge_mesh():
    # Roblox wedge: full bottom, full back (+Z), slope from bottom-front to top-back
    v = np.array([
        [-.5, -.5, -.5], [.5, -.5, -.5],  # bottom front
        [-.5, -.5, .5], [.5, -.5, .5],    # bottom back
        [-.5, .5, .5], [.5, .5, .5],      # top back
    ])
    tris = [(0, 1, 3), (0, 3, 2),   # bottom
            (2, 3, 5), (2, 5, 4),   # back
            (0, 4, 5), (0, 5, 1),   # slope
            (0, 2, 4), (1, 5, 3)]   # sides
    return v, tris


def cylinder_mesh(n=18):
    v = []
    for side in (-.5, .5):
        for i in range(n):
            a = 2 * math.pi * i / n
            v.append([side, .5 * math.cos(a), .5 * math.sin(a)])
    v.append([-.5, 0, 0])
    v.append([.5, 0, 0])
    tris = []
    for i in range(n):
        j = (i + 1) % n
        tris += [(i, j, n + j), (i, n + j, n + i)]
        tris.append((2 * n, j, i))
        tris.append((2 * n + 1, n + i, n + j))
    return np.array(v), tris


def ball_mesh(n=10):
    v = []
    for i in range(n + 1):
        t = math.pi * i / n
        for j in range(n):
            p = 2 * math.pi * j / n
            v.append([.5 * math.sin(t) * math.cos(p), .5 * math.cos(t), .5 * math.sin(t) * math.sin(p)])
    tris = []
    for i in range(n):
        for j in range(n):
            a = i * n + j
            b = i * n + (j + 1) % n
            c = (i + 1) * n + j
            d = (i + 1) * n + (j + 1) % n
            tris += [(a, b, d), (a, d, c)]
    return np.array(v), tris


MESHES = {"Block": block_mesh(), "Wedge": wedge_mesh(), "Cylinder": cylinder_mesh(), "Ball": ball_mesh()}


def car_triangles(car):
    tris, cols, alphas = [], [], []
    for p in car["parts"]:
        mesh = MESHES.get(p["s"], MESHES["Block"])
        verts, faces = mesh
        size = np.array(p["size"])
        cf = p["cf"]
        pos = np.array(cf[0:3])
        rot = np.array(cf[3:12]).reshape(3, 3)
        world = (rot @ (verts * size).T).T + pos
        for f in faces:
            tris.append(world[list(f)])
            cols.append(p["c"])
            alphas.append(p["t"])
    return np.array(tris), np.array(cols), np.array(alphas)


def render(tris, cols, alphas, view_dir, w, h, scale, center):
    d = np.array(view_dir, dtype=float)
    d /= np.linalg.norm(d)
    up_world = np.array([0, 1, 0.0])
    right = np.cross(d, up_world)
    right /= np.linalg.norm(right)
    up = np.cross(right, d)
    rel = tris - center
    sx = rel @ right * scale + w / 2
    sy = -(rel @ up) * scale + h * 0.58
    depth = rel @ d
    img = np.full((h, w, 3), 236, dtype=float)
    img[int(h * 0.62):, :] = [205, 210, 200]
    zbuf = np.full((h, w), np.inf)
    light = np.array([-0.4, 0.85, -0.35])
    light /= np.linalg.norm(light)
    for i in range(len(tris)):
        p = tris[i]
        n = np.cross(p[1] - p[0], p[2] - p[0])
        nl = np.linalg.norm(n)
        if nl < 1e-9:
            continue
        n /= nl
        if np.dot(n, d) > 0:  # back face (meshes are wound consistently enough; draw both)
            n = -n
        shade = 0.45 + 0.55 * max(0.0, float(np.dot(n, light)))
        col = np.array(cols[i]) * 255 * shade
        if alphas[i] > 0.2:
            col = col * 0.6 + np.array([150, 175, 205]) * 0.4
        xs, ys, zs = sx[i], sy[i], depth[i]
        x0, x1 = int(max(0, math.floor(xs.min()))), int(min(w - 1, math.ceil(xs.max())))
        y0, y1 = int(max(0, math.floor(ys.min()))), int(min(h - 1, math.ceil(ys.max())))
        if x0 > x1 or y0 > y1:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
        (ax, bx, cx), (ay, by, cy) = xs, ys
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
        l2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
        l3 = 1 - l1 - l2
        mask = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
        if not mask.any():
            continue
        z = l1 * zs[0] + l2 * zs[1] + l3 * zs[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        upd = mask & (z < sub)
        sub[upd] = z[upd]
        region = img[y0:y1 + 1, x0:x1 + 1]
        region[upd] = col
    return img.astype(np.uint8)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    only = sys.argv[3].split(",") if len(sys.argv) > 3 else None
    cars = json.load(open(src))
    if only:
        cars = [c for c in cars if c["id"] in only]
    cw, ch = 420, 260
    cols_n = 2
    sheet = Image.new("RGB", (cw * cols_n, ch * len(cars)), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for row, car in enumerate(cars):
        tris, cols, alphas = car_triangles(car)
        pts = tris.reshape(-1, 3)
        lo, hi = pts.min(axis=0), pts.max(axis=0)
        center = (lo + hi) / 2
        extent = max(hi[0] - lo[0], hi[2] - lo[2], (hi[1] - lo[1]) * 1.6)
        scale = cw * 0.62 / extent
        views = [(0.75, -0.45, 0.85), (-0.8, -0.4, -0.75)]
        for col, v in enumerate(views):
            img = render(tris, cols, alphas, v, cw, ch, scale, center)
            sheet.paste(Image.fromarray(img), (col * cw, row * ch))
        draw.text((8, row * ch + 6), f'{car["name"]} ({car["id"]}) parts={len(car["parts"])}', fill=(0, 0, 0))
    sheet.save(dst)
    print("wrote", dst)


if __name__ == "__main__":
    main()
