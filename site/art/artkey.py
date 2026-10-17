"""artkey — shared image helpers for scripts/art-*.sh (imported via sys.path; PIL only, no numpy).

keyout(im): flat #ff00ff chroma backdrop → RGBA (edge flood + bright-magenta islands, soft fringe, despill).
unglow(im): black backdrop → RGBA, alpha = max channel, colour un-premultiplied (neon/glow emblems).
webp_under(im, kb, ...): encode webp, stepping quality down until ≤ kb KB; returns (bytes, quality).
"""
import io
from collections import deque

from PIL import Image, ImageFilter


def magness(px):
    return [min(r, b) - g for r, g, b in px]          # ~255 on the key, ≤0 on skin/hair


def keyout(im):
    im = im.convert("RGB")
    w, h = im.size
    px = list(im.getdata())
    m = magness(px)
    bg = bytearray(w * h)
    q = deque(i for i in range(w * h) if m[i] > 130 and min(px[i][0], px[i][2]) > 180)  # bright-magenta holes
    q.extend(i for i in list(range(w)) + list(range(w * (h - 1), w * h)) if m[i] > 120)
    for i in q:
        bg[i] = 1
    while q:                                         # grow through near-magenta neighbours
        i = q.popleft(); x = i % w
        for j in (i - w, i + w, i - 1 if x else -1, i + 1 if x < w - 1 else -1):
            if 0 <= j < w * h and not bg[j] and m[j] > 90:
                bg[j] = 1; q.append(j)
    mask = Image.frombytes("L", im.size, bytes(bg))
    zone = mask.filter(ImageFilter.MaxFilter(7)).tobytes()    # ≤3px from bg: fade + despill
    near = mask.filter(ImageFilter.MaxFilter(25)).tobytes()   # ≤12px: despill strong spill only (thin hair)
    out = []
    for i, (r, g, b) in enumerate(px):
        if bg[i]:
            out.append((0, 0, 0, 0)); continue
        if zone[i] and m[i] > 0:                        # soft fringe: fade by spill, then strip the spill
            a = max(0, min(255, int(255 * (1 - m[i] / 120))))
            out.append((r - m[i], g, b - m[i], a))
        elif near[i] and m[i] > 30:
            out.append((r - m[i], g, b - m[i], 255))
        else:
            out.append((r, g, b, 255))
    o = Image.new("RGBA", im.size); o.putdata(out)
    return o


def unglow(im, floor=18):
    out = []
    for r, g, b in im.convert("RGB").getdata():
        a = max(r, g, b)
        a = 0 if a <= floor else min(255, int((a - floor) * 255 / (255 - floor)))
        out.append((0, 0, 0, 0) if not a else (min(255, r * 255 // max(r, g, b)), min(255, g * 255 // max(r, g, b)),
                                               min(255, b * 255 // max(r, g, b)), a))
    o = Image.new("RGBA", im.size); o.putdata(out)
    return o


def webp_under(im, kb, start=90, alpha_q=100, floor=20):
    for q in range(start, floor - 1, -5):
        buf = io.BytesIO(); im.save(buf, "WEBP", quality=q, alpha_quality=alpha_q, method=6)
        if buf.tell() <= kb * 1024:
            break
    return buf.getvalue(), q


def components(mask, small=0.002):
    """mask: L image (255 = foreground). Returns [(bbox, area, labelset)] of big 4-connected blobs; small
    blobs whose centre falls inside a big blob's bbox (+4%) are merged into it, others dropped."""
    w, h = mask.size
    px, lab, blobs = mask.tobytes(), [0] * (w * h), []
    for s in range(w * h):
        if not px[s] or lab[s]:
            continue
        n = len(blobs) + 1; lab[s] = n; q = deque([s]); x0, y0, x1, y1, area = w, h, 0, 0, 0
        while q:
            i = q.popleft(); x, y = i % w, i // w; area += 1
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
            for j in (i - w, i + w, i - 1 if x else -1, i + 1 if x < w - 1 else -1):
                if 0 <= j < w * h and px[j] and not lab[j]:
                    lab[j] = n; q.append(j)
        blobs.append([(x0, y0, x1 + 1, y1 + 1), area, {n}])
    big = [b for b in blobs if b[1] >= small * w * h]
    pad = 0.04 * max(w, h)
    for b in blobs:
        if b[1] >= small * w * h:
            continue
        cx, cy = (b[0][0] + b[0][2]) / 2, (b[0][1] + b[0][3]) / 2
        for g in big:
            x0, y0, x1, y1 = g[0]
            if x0 - pad <= cx <= x1 + pad and y0 - pad <= cy <= y1 + pad:
                g[2] |= b[2]
                g[0] = (min(x0, b[0][0]), min(y0, b[0][1]), max(x1, b[0][2]), max(y1, b[0][3])); break
    return big, lab


def despeck(im, minpx=40):
    """Clear alpha islands smaller than minpx (keying dust, stray sheet specks); im is RGBA."""
    a = im.getchannel("A").point(lambda v: 255 if v > 24 else 0)
    blobs, lab = components(a, small=0)
    tiny = {n for b in blobs if b[1] < minpx for n in b[2]}
    if not tiny:
        return im
    px = list(im.getdata())
    im = im.copy(); im.putdata([(0, 0, 0, 0) if lab[i] in tiny else p for i, p in enumerate(px)])
    return im
