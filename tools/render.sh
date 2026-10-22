#!/usr/bin/env bash
# Renders preview images of every car, the service vehicles, a service plot, the map and the UI (needs python3 + numpy + pillow).
# Run tools/test.sh first: it writes the geometry dumps to tests/out/.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/render_gallery.py tests/out/cars.json docs/cars.png
python3 tools/render_map.py tests/out/map.json tests/out/heightmap.json tests/out/map.png
python3 -c "from PIL import Image; Image.open('tests/out/map.png').resize((1100, 1100), Image.LANCZOS).save('docs/map.png')"
python3 tools/render_gallery.py tests/out/service.json docs/service.png
python3 tools/render_plot.py tests/out/plot.json docs/service_plot.png
# interface screenshots (dumped by tests/client.spec.luau), drawn over the plot render
for n in hud orders business workshop garage result; do
  python3 tools/render_ui.py tests/out/ui_$n.json tests/out/ui_$n.png docs/service_plot.png
  python3 -c "from PIL import Image; Image.open('tests/out/ui_$n.png').resize((1280, 720), Image.LANCZOS).save('docs/ui_$n.png')"
done
