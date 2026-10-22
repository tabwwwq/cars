"""Renders a UI dump (tests/harness/guidump.luau) to a PNG so screens can be
reviewed without Roblox Studio. It approximates the Roblox GUI engine:
UDim2 sizes, anchor points, UIPadding, UIListLayout, UIGridLayout,
AutomaticSize, UICorner, UIStroke, UIGradient, UIScale, clipping, rotation,
text (TextScaled, wrapping, alignment, strokes) and colour emoji.

Usage: python3 tools/render_ui.py tests/out/ui_hud.json out.png [background.png]
Fonts: Fredoka / Montserrat TTFs are used when found in $UI_FONTS or
tools/fonts (Roblox FredokaOne / Gotham look-alikes); DejaVu otherwise.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIRS = [os.environ.get("UI_FONTS", ""), os.path.join(HERE, "fonts")]
DEJAVU = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
DEJAVU_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
DEJAVU_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
EMOJI = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"


def find_font(name):
    for d in FONT_DIRS:
        if d and os.path.exists(os.path.join(d, name)):
            return os.path.join(d, name)
    return None


FONT_MAP = {
    # roblox font -> (file, variable weight)
    "FredokaOne": ("Fredoka.ttf", 620),
    "GothamBlack": ("Montserrat.ttf", 900),
    "GothamBold": ("Montserrat.ttf", 700),
    "GothamMedium": ("Montserrat.ttf", 500),
    "Gotham": ("Montserrat.ttf", 400),
    "BuilderSansExtraBold": ("Montserrat.ttf", 800),
    "BuilderSansBold": ("Montserrat.ttf", 700),
    "BuilderSans": ("Montserrat.ttf", 500),
    "LuckiestGuy": ("Fredoka.ttf", 700),
}

_fonts = {}
_cmaps = {}


def cmap_of(path):
    if path not in _cmaps:
        try:
            from fontTools.ttLib import TTFont

            _cmaps[path] = set(TTFont(path, lazy=True).getBestCmap().keys())
        except Exception:
            _cmaps[path] = None
    return _cmaps[path]


def font_for(name, size):
    size = max(4, int(round(size)))
    key = (name, size)
    if key in _fonts:
        return _fonts[key]
    path, weight = None, None
    if name in FONT_MAP:
        f, weight = FONT_MAP[name]
        path = find_font(f)
    if name == "Code":
        path = DEJAVU_MONO
    if not path:
        path = DEJAVU if name not in ("Gotham", "GothamMedium", "SourceSans") else DEJAVU_REG
        weight = None
    font = ImageFont.truetype(path, size)
    if weight:
        try:
            font.set_variation_by_axes([weight] + ([100] if "Fredoka" in path else []))
        except Exception:
            try:
                font.set_variation_by_axes([weight])
            except Exception:
                pass
    _fonts[key] = (font, path)
    return _fonts[key]


_emoji_font = None
_emoji_cache = {}


def emoji_image(ch, size):
    global _emoji_font
    key = (ch, size)
    if key in _emoji_cache:
        return _emoji_cache[key]
    if _emoji_font is None:
        _emoji_font = ImageFont.truetype(EMOJI, 109)
    img = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((10, 10), ch, font=_emoji_font, embedded_color=True)
    bbox = img.getbbox()
    if not bbox:
        _emoji_cache[key] = None
        return None
    img = img.crop(bbox)
    scale = size / 109 * 1.05
    img = img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))), Image.LANCZOS)
    _emoji_cache[key] = img
    return img


def is_emoji(ch, path):
    cp = ord(ch)
    if cp in (0xFE0F, 0x200D):
        return True
    if cp >= 0x1F000:
        return True
    cmap = cmap_of(path)
    if cmap is not None and cp not in cmap:
        emap = cmap_of(EMOJI)
        return emap is not None and cp in emap
    return False


def fallback_has(ch):
    cmap = cmap_of(DEJAVU)
    return cmap is None or ord(ch) in cmap


# ----------------------------------------------------------------------------
# text


def split_runs(text, path):
    runs = []
    for ch in text:
        kind = "e" if is_emoji(ch, path) else "t"
        if ch in ("️", "‍"):
            continue
        if runs and runs[-1][0] == kind and kind == "t":
            runs[-1][1] += ch
        else:
            runs.append([kind, ch])
    return runs


def run_width(runs, font, path, size):
    w = 0
    for kind, s in runs:
        if kind == "e":
            img = emoji_image(s, size)
            w += (img.width if img else size) + size * 0.08
        else:
            w += font.getlength(s)
    return w


def wrap_lines(text, font, path, size, width, wrap):
    lines = []
    for para in text.split("\n"):
        if not wrap:
            lines.append(para)
            continue
        words = para.split(" ")
        cur = ""
        for word in words:
            cand = word if not cur else cur + " " + word
            if run_width(split_runs(cand, path), font, path, size) <= width or not cur:
                cur = cand
            else:
                lines.append(cur)
                cur = word
        lines.append(cur)
    return lines


def measure_text(text, fontname, size, width=None, wrap=False):
    font, path = font_for(fontname, size)
    lines = wrap_lines(text, font, path, size, width or 1e9, wrap)
    w = max((run_width(split_runs(l, path), font, path, size) for l in lines), default=0)
    return w, len(lines) * size * 1.15


def draw_text(layer, box, n, scale_factor):
    text = n.get("t", "")
    if text == "":
        return
    x0, y0, w, h = box
    fontname = n.get("f") or "Legacy"
    size = n.get("ts", 14)
    wrap = n.get("tw") or n.get("tsc")
    if n.get("tsc"):
        # largest size that fits (Roblox caps TextScaled at 100)
        lo, hi = int(n.get("mints", 4)), int(n.get("maxts", 100))
        while lo < hi:
            mid = (lo + hi + 1) // 2
            tw, th = measure_text(text, fontname, mid, w, True)
            if tw <= w + 0.5 and th <= h + 0.5:
                lo = mid
            else:
                hi = mid - 1
        size = lo
    font, path = font_for(fontname, size)
    lines = wrap_lines(text, font, path, size, w, wrap)
    if n.get("trunc") and not wrap:
        fixed = []
        for line in lines:
            if run_width(split_runs(line, path), font, path, size) > w:
                while line and run_width(split_runs(line + "…", path), font, path, size) > w:
                    line = line[:-1]
                line = line + "…"
            fixed.append(line)
        lines = fixed
    line_h = size * 1.15
    total_h = len(lines) * line_h
    ya = n.get("ya") or "Center"
    xa = n.get("xa") or "Center"
    if ya == "Top":
        ty = y0
    elif ya == "Bottom":
        ty = y0 + h - total_h
    else:
        ty = y0 + (h - total_h) / 2
    color = tuple(int(c * 255) for c in (n.get("tc") or [0.1, 0.16, 0.2]))
    alpha = int(255 * (1 - n.get("tt", 0)))
    if alpha <= 0:
        return
    stroke = n.get("stroke")
    stroke_w, stroke_fill = 0, None
    if stroke and (stroke.get("mode") in (None, "Contextual")) and stroke.get("t", 0) < 1:
        stroke_w = max(1, int(round(stroke.get("th", 1))))
        stroke_fill = tuple(int(c * 255) for c in stroke["c"]) + (int(255 * (1 - stroke.get("t", 0))),)
    elif n.get("tst", 1) < 1:
        stroke_w = 1
        stroke_fill = tuple(int(c * 255) for c in (n.get("tsc3") or [0, 0, 0])) + (int(255 * (1 - n["tst"])),)
    draw = ImageDraw.Draw(layer)
    for i, line in enumerate(lines):
        runs = split_runs(line, path)
        lw = run_width(runs, font, path, size)
        if xa == "Left":
            tx = x0
        elif xa == "Right":
            tx = x0 + w - lw
        else:
            tx = x0 + (w - lw) / 2
        yy = ty + i * line_h
        for kind, s in runs:
            if kind == "e":
                img = emoji_image(s, size)
                if img:
                    if alpha < 255:
                        a = img.split()[3].point(lambda v: v * alpha // 255)
                        img = img.copy()
                        img.putalpha(a)
                    layer.alpha_composite(img, (int(tx), int(yy + (line_h - img.height) / 2)))
                    tx += img.width + size * 0.08
                else:
                    tx += size
            else:
                f = font
                if not all(ord(c) in (cmap_of(path) or {ord(c)}) for c in s):
                    f = ImageFont.truetype(DEJAVU, max(4, int(size)))
                draw.text(
                    (tx, yy + (line_h - size) / 2 - size * 0.12),
                    s,
                    font=f,
                    fill=color + (alpha,),
                    stroke_width=stroke_w,
                    stroke_fill=stroke_fill,
                )
                tx += f.getlength(s)


# ----------------------------------------------------------------------------
# layout


def udim(u, size):
    return u[0] * size + u[1]


def child_size(c, cw, ch):
    s = c.get("size") or [0, 100, 0, 100]
    w, h = udim(s[0:2], cw), udim(s[2:4], ch)
    mn = c.get("minsize")
    if mn:
        w, h = max(w, mn[0]), max(h, mn[1])
    return [w, h]


def padding_of(n, w, h):
    p = n.get("pad")
    if not p:
        return 0, 0, 0, 0
    return udim(p[0], w), udim(p[1], w), udim(p[2], h), udim(p[3], h)


def layout(n, x, y, w, h):
    """n gets abs rect; children laid out inside."""
    n["_rect"] = [x, y, w, h]
    kids = [k for k in n.get("kids", []) if k.get("v", True)]
    pl, pr, pt, pb = padding_of(n, w, h)
    cx, cy, cw, ch = x + pl, y + pt, max(0, w - pl - pr), max(0, h - pt - pb)
    if n.get("c") == "ScrollingFrame":
        cv = n.get("canvas") or [0, 0]
        cy -= cv[1]
        cx -= cv[0]
    for k in kids:
        k["_size"] = child_size(k, cw, ch)
        auto_size(k)
    order = sorted(range(len(kids)), key=lambda i: (kids[i].get("lo", 0), i))
    if n.get("list"):
        L = n["list"]
        vertical = (L.get("dir") or "Vertical") == "Vertical"
        pad = udim(L.get("pad") or [0, 0], ch if vertical else cw)
        seq = [kids[i] for i in order]
        total = sum(k["_size"][1 if vertical else 0] for k in seq) + pad * max(0, len(seq) - 1)
        if vertical:
            va = L.get("va") or "Top"
            pos = cy if va == "Top" else (cy + (ch - total) / 2 if va == "Center" else cy + ch - total)
            for k in seq:
                kw, kh = k["_size"]
                ha = L.get("ha") or "Left"
                kx = cx if ha == "Left" else (cx + (cw - kw) / 2 if ha == "Center" else cx + cw - kw)
                layout(k, kx, pos, kw, kh)
                pos += kh + pad
        else:
            ha = L.get("ha") or "Left"
            pos = cx if ha == "Left" else (cx + (cw - total) / 2 if ha == "Center" else cx + cw - total)
            for k in seq:
                kw, kh = k["_size"]
                va = L.get("va") or "Top"
                ky = cy if va == "Top" else (cy + (ch - kh) / 2 if va == "Center" else cy + ch - kh)
                layout(k, pos, ky, kw, kh)
                pos += kw + pad
    elif n.get("grid"):
        G = n["grid"]
        cell = G.get("cell") or [0, 100, 0, 100]
        cpad = G.get("pad") or [0, 5, 0, 5]
        cwid, chei = udim(cell[0:2], cw), udim(cell[2:4], ch)
        px, py = udim(cpad[0:2], cw), udim(cpad[2:4], ch)
        cols = max(1, int((cw + px) // (cwid + px))) if cwid + px > 0 else 1
        seq = [kids[i] for i in order]
        rowsw = min(cols, len(seq)) * cwid + max(0, min(cols, len(seq)) - 1) * px
        ha = G.get("ha") or "Left"
        ox = 0 if ha == "Left" else ((cw - rowsw) / 2 if ha == "Center" else cw - rowsw)
        for i, k in enumerate(seq):
            col, row = i % cols, i // cols
            layout(k, cx + ox + col * (cwid + px), cy + row * (chei + py), cwid, chei)
    else:
        for k in kids:
            kw, kh = k["_size"]
            p = k.get("pos") or [0, 0, 0, 0]
            ap = k.get("ap") or [0, 0]
            kx = cx + udim(p[0:2], cw) - ap[0] * kw
            ky = cy + udim(p[2:4], ch) - ap[1] * kh
            layout(k, kx, ky, kw, kh)


def auto_size(n):
    a = n.get("as")
    if not a or a == "None":
        return
    w, h = n["_size"]
    pl, pr, pt, pb = padding_of(n, w, h)
    if n.get("t") is not None and n.get("t") != "":
        tw, th = measure_text(n["t"], n.get("f") or "Legacy", n.get("ts", 14), w if a == "Y" else None, n.get("tw"))
        if a in ("X", "XY"):
            w = max(w, tw + pl + pr + 2)
        if a in ("Y", "XY"):
            h = max(h, th + pt + pb)
    kids = [k for k in n.get("kids", []) if k.get("v", True)]
    if kids:
        # lay out in a scratch pass to measure
        n["_size"] = [w, h]
        layout(n, 0, 0, w, h)
        maxx = max((k["_rect"][0] + k["_rect"][2] for k in kids), default=0)
        maxy = max((k["_rect"][1] + k["_rect"][3] for k in kids), default=0)
        if a in ("X", "XY"):
            w = max(w, maxx + pr)
        if a in ("Y", "XY"):
            h = max(h, maxy + pb)
    n["_size"] = [w, h]


# ----------------------------------------------------------------------------
# drawing


def corner_radius(n, w, h):
    c = n.get("corner")
    if c is None:
        return 0
    return max(0, min(udim(c, min(w, h)), min(w, h) / 2))


def rounded_mask(size, radius, ss=3):
    w, h = size
    big = Image.new("L", (max(1, w * ss), max(1, h * ss)), 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, w * ss - 1, h * ss - 1], radius=radius * ss, fill=255)
    return big.resize((max(1, w), max(1, h)), Image.LANCZOS)


def gradient_image(w, h, grad):
    """RGB multiplier and alpha multiplier images for a UIGradient."""
    import numpy as np

    rot = math.radians(grad.get("rot", 0))
    dx, dy = math.cos(rot), math.sin(rot)
    cs = grad.get("cs") or [[0, [1, 1, 1]], [1, [1, 1, 1]]]
    ts = grad.get("ts") or [[0, 0], [1, 0]]
    # project every pixel onto the gradient axis, 0..1 across the box
    proj = [cx * dx + cy * dy for cx, cy in ((0, 0), (w, 0), (0, h), (w, h))]
    lo, hi = min(proj), max(proj)
    xs = (np.arange(w) + 0.5)[None, :]
    ys = (np.arange(h) + 0.5)[:, None]
    t = np.clip((xs * dx + ys * dy - lo) / max(1e-6, hi - lo), 0, 1)
    times = [k[0] for k in cs]
    rgb = np.stack([np.interp(t, times, [k[1][j] for k in cs]) for j in range(3)], axis=-1)
    alpha = 1 - np.interp(t, [k[0] for k in ts], [k[1] for k in ts])
    return (
        Image.fromarray((rgb * 255).astype("uint8"), "RGB"),
        Image.fromarray((alpha * 255).astype("uint8"), "L"),
    )


def render_viewport(vp, w, h):
    """Flat-shaded 3D preview of a ViewportFrame's parts (orthographic)."""
    import numpy as np

    sys.path.insert(0, HERE)
    from render_cars import car_triangles

    tris, cols, alphas = car_triangles({"parts": vp["parts"]})
    if len(tris) == 0 or w < 4 or h < 4:
        return None
    d = np.array(vp.get("look") or [0.75, -0.45, 0.85], dtype=float)
    d /= np.linalg.norm(d)
    right = np.cross(d, [0, 1, 0.0])
    right /= max(1e-9, np.linalg.norm(right))
    up = np.cross(right, d)
    pts = tris.reshape(-1, 3)
    center = (pts.min(axis=0) + pts.max(axis=0)) / 2
    rel = tris - center
    px, py = rel @ right, rel @ up
    span = max(px.max() - px.min(), (py.max() - py.min()) * w / h, 1e-6)
    scale = w * 0.86 / span
    sx = px * scale + w / 2
    sy = -py * scale + h / 2
    depth = rel @ d
    img = np.zeros((h, w, 4), dtype=float)
    zbuf = np.full((h, w), np.inf)
    light = np.array([-0.4, 0.85, -0.35])
    light /= np.linalg.norm(light)
    for i in range(len(tris)):
        p = tris[i]
        nrm = np.cross(p[1] - p[0], p[2] - p[0])
        nl = np.linalg.norm(nrm)
        if nl < 1e-9:
            continue
        nrm /= nl
        if np.dot(nrm, d) > 0:
            nrm = -nrm
        shade = 0.5 + 0.5 * max(0.0, float(np.dot(nrm, light)))
        col = np.array(cols[i]) * 255 * shade
        xs, ys, zs = sx[i], sy[i], depth[i]
        x0, x1 = int(max(0, math.floor(xs.min()))), int(min(w - 1, math.ceil(xs.max())))
        y0, y1 = int(max(0, math.floor(ys.min()))), int(min(h - 1, math.ceil(ys.max())))
        if x0 > x1 or y0 > y1:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
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
        sub = zbuf[y0 : y1 + 1, x0 : x1 + 1]
        upd = mask & (z < sub)
        sub[upd] = z[upd]
        region = img[y0 : y1 + 1, x0 : x1 + 1]
        region[upd] = list(col) + [255 * (1 - min(0.6, alphas[i]))]
    return Image.fromarray(img.astype("uint8"), "RGBA")


def paint_box(canvas, n, ox, oy):
    x, y, w, h = n["_rect"]
    x, y = x + ox, y + oy
    iw, ih = int(round(w)), int(round(h))
    if iw <= 0 or ih <= 0:
        return
    r = corner_radius(n, w, h)
    bt = n.get("bt", 0)
    if n.get("c") == "ScrollingFrame" and n.get("bt") is None:
        bt = 0
    stroke = n.get("stroke")
    is_text = n.get("t") is not None
    # outer stroke (Border mode, or any stroke on a non-text object)
    if stroke and stroke.get("t", 0) < 1 and (stroke.get("mode") == "Border" or not is_text):
        th = stroke.get("th", 1)
        tw, thh = int(round(w + th * 2)), int(round(h + th * 2))
        outer = rounded_mask((tw, thh), r + th if r > 0 else 0)
        inner = Image.new("L", (tw, thh), 0)
        inner.paste(rounded_mask((iw, ih), r), (int(round(th)), int(round(th))))
        ring = Image.eval(outer, lambda v: v)
        ring = Image.composite(Image.new("L", (tw, thh), 0), ring, inner.point(lambda v: 255 if v > 127 else 0))
        col = tuple(int(c * 255) for c in stroke["c"])
        layer = Image.new("RGBA", (tw, thh), col + (0,))
        layer.putalpha(ring.point(lambda v: int(v * (1 - stroke.get("t", 0)))))
        canvas.alpha_composite(layer, (int(round(x - th)), int(round(y - th))))
    if bt < 1:
        col = tuple(int(c * 255) for c in (n.get("bg") or [1, 1, 1]))
        layer = Image.new("RGBA", (iw, ih), col + (255,))
        alpha = rounded_mask((iw, ih), r) if r > 0 else Image.new("L", (iw, ih), 255)
        grad = n.get("grad")
        if grad:
            g_rgb, g_a = gradient_image(iw, ih, grad)
            base = Image.new("RGB", (iw, ih), col)
            from PIL import ImageChops

            layer = ImageChops.multiply(base, g_rgb).convert("RGBA")
            alpha = ImageChops.multiply(alpha, g_a)
        alpha = alpha.point(lambda v: int(v * (1 - bt)))
        layer.putalpha(alpha)
        canvas.alpha_composite(layer, (int(round(x)), int(round(y))))
        if r == 0 and n.get("bs", 1) > 0 and not stroke:
            bc = tuple(int(c * 255) for c in (n.get("bc") or [27 / 255, 42 / 255, 53 / 255]))
            ImageDraw.Draw(canvas).rectangle([x - 1, y - 1, x + w, y + h], outline=bc + (int(255 * (1 - bt)),))
    if n.get("c") == "ViewportFrame":
        vp = n.get("vp")
        img = render_viewport(vp, iw, ih) if vp and vp.get("parts") else None
        if img is not None:
            canvas.alpha_composite(img, (int(round(x)), int(round(y))))
    if is_text:
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        pl, pr, pt, pb = padding_of(n, w, h)
        draw_text(layer, (x + pl, y + pt, w - pl - pr, h - pt - pb), n, 1)
        if n.get("grad"):
            pass
        canvas.alpha_composite(layer)


def draw_node(canvas, n, ox=0, oy=0):
    if not n.get("v", True) or "_rect" not in n:
        return
    x, y, w, h = n["_rect"]
    rot = n.get("rot", 0) or 0
    kids = [k for k in n.get("kids", []) if k.get("v", True)]
    clip = n.get("clip") or n.get("c") in ("ScrollingFrame", "CanvasGroup")
    if rot and not kids and not n.get("t"):
        # rotated plain frame: draw as a polygon
        if n.get("bt", 0) < 1:
            cxp, cyp = x + ox + w / 2, y + oy + h / 2
            a = math.radians(rot)
            pts = []
            for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                px, py = sx * w / 2, sy * h / 2
                pts.append((cxp + px * math.cos(a) - py * math.sin(a), cyp + px * math.sin(a) + py * math.cos(a)))
            col = tuple(int(c * 255) for c in (n.get("bg") or [1, 1, 1]))
            layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            ImageDraw.Draw(layer).polygon(pts, fill=col + (int(255 * (1 - n.get("bt", 0))),))
            canvas.alpha_composite(layer)
        return
    if rot or clip:
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        paint_box(layer, n, ox, oy)
        sub = Image.new("RGBA", canvas.size, (0, 0, 0, 0)) if clip else layer
        for k in sorted(kids, key=lambda k: k.get("z", 1)):
            draw_node(sub, k, ox, oy)
        if clip:
            mask = Image.new("L", canvas.size, 0)
            r = corner_radius(n, w, h) if n.get("c") == "CanvasGroup" else 0
            iw, ih = max(1, int(round(w))), max(1, int(round(h)))
            mask.paste(rounded_mask((iw, ih), r) if r else Image.new("L", (iw, ih), 255), (int(round(x + ox)), int(round(y + oy))))
            sub.putalpha(Image.composite(sub.split()[3], Image.new("L", canvas.size, 0), mask))
            layer.alpha_composite(sub)
        if rot:
            layer = layer.rotate(-rot, resample=Image.BICUBIC, center=(x + ox + w / 2, y + oy + h / 2))
        canvas.alpha_composite(layer)
        return
    paint_box(canvas, n, ox, oy)
    for k in sorted(kids, key=lambda k: k.get("z", 1)):
        draw_node(canvas, k, ox, oy)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    bg = sys.argv[3] if len(sys.argv) > 3 else None
    data = json.load(open(src))
    vw, vh = data["viewport"]
    vw, vh = int(vw), int(vh)
    if bg and os.path.exists(bg):
        back = Image.open(bg).convert("RGBA")
        s = max(vw / back.width, vh / back.height)
        back = back.resize((int(back.width * s) + 1, int(back.height * s) + 1), Image.LANCZOS)
        back = back.crop((0, 0, vw, vh))
    else:
        back = Image.new("RGBA", (vw, vh), (120, 150, 170, 255))
    out = back
    for g in data["guis"]:
        scale = g.get("scale", 1) or 1
        lw, lh = int(vw / scale), int(vh / scale)
        layer = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
        root = {"c": "Frame", "kids": g["kids"], "bt": 1}
        layout(root, 0, 0, lw, lh)
        for k in sorted(root["kids"], key=lambda k: k.get("z", 1)):
            draw_node(layer, k)
        if scale != 1:
            layer = layer.resize((vw, vh), Image.LANCZOS)
        out.alpha_composite(layer)
    out.convert("RGB").save(dst)
    print("wrote", dst)


if __name__ == "__main__":
    main()
