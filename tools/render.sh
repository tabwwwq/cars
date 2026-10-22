#!/usr/bin/env bash
# Renders preview images of every car, the service vehicles, a service plot and the map (needs python3 + numpy + pillow).
# Run tools/test.sh first: it writes the geometry dumps to tests/out/.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/render_gallery.py tests/out/cars.json docs/cars.png
python3 tools/render_map.py tests/out/map.json tests/out/heightmap.json tests/out/map.png
python3 -c "from PIL import Image; Image.open('tests/out/map.png').resize((1100, 1100), Image.LANCZOS).save('docs/map.png')"
python3 tools/render_gallery.py tests/out/service.json docs/service.png
python3 tools/render_plot.py tests/out/plot.json docs/service_plot.png
