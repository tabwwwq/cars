"""Perspective-free 3/4 render of one dressed car-service plot (README image).

Usage: python3 tools/render_plot.py tests/out/plot.json docs/service_plot.png
"""
import json
import sys

from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from render_cars import car_triangles, render  # noqa: E402


def main():
    plot = json.load(open(sys.argv[1]))[0]
    # drop the roof so the bays are visible from above
    plot["parts"] = [p for p in plot["parts"] if not (p["cf"] and float(p["cf"][1]) > 23.5 and float(p["size"][0]) > 150)]
    tris, colors, alphas = car_triangles(plot)
    pts = tris.reshape(-1, 3)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    center = (lo + hi) / 2
    w, h = 1600, 1000
    img = render(tris, colors, alphas, (0.55, -0.75, -0.65), w, h, w * 0.62 / (hi[0] - lo[0]), center)
    Image.fromarray(img).save(sys.argv[2])
    print("wrote", sys.argv[2])


if __name__ == "__main__":
    main()
