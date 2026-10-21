"""Compact gallery of every car (front 3/4 view) for the README.

Usage: python3 tools/render_gallery.py tests/out/cars.json docs/cars.png
"""
import json
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from render_cars import car_triangles, render  # noqa: E402


def main():
    cars = json.load(open(sys.argv[1]))
    cw, ch, cols = 340, 210, 4
    rows = (len(cars) + cols - 1) // cols
    sheet = Image.new("RGB", (cw * cols, ch * rows), (236, 236, 236))
    draw = ImageDraw.Draw(sheet)
    for i, car in enumerate(cars):
        tris, colors, alphas = car_triangles(car)
        pts = tris.reshape(-1, 3)
        lo, hi = pts.min(axis=0), pts.max(axis=0)
        center = (lo + hi) / 2
        extent = max(hi[0] - lo[0], hi[2] - lo[2], (hi[1] - lo[1]) * 1.6)
        img = render(tris, colors, alphas, (0.75, -0.45, 0.85), cw, ch, cw * 0.66 / extent, center)
        x, y = (i % cols) * cw, (i // cols) * ch
        sheet.paste(Image.fromarray(img), (x, y))
        draw.text((x + 10, y + 8), car["name"], fill=(20, 20, 24))
    sheet.save(sys.argv[2])
    print("wrote", sys.argv[2], sheet.size)


if __name__ == "__main__":
    main()
