"""Shared helpers for the hidden-object art pipeline (cut-out cleanup, scene matching, shadows, occluders).
Used by compose.py (hand-placed scenes), library.py (object library) and layout.py (random layouts)."""
from PIL import Image, ImageFilter, ImageDraw
import numpy as np


def keep_main_blob(mask):
    """Connected region (4-neighbour) containing the centre of the mask's bounding box, grown by repeated dilation.
    (Original PoC behaviour, kept for the hand-placed scenes.)"""
    ys, xs = np.nonzero(mask)
    cy, cx = (ys.min() + ys.max()) // 2, (xs.min() + xs.max()) // 2
    if not mask[cy, cx]:
        k = np.argmin((ys - cy) ** 2 + (xs - cx) ** 2); cy, cx = ys[k], xs[k]
    region = np.zeros_like(mask); region[cy, cx] = True
    while True:
        grown = region.copy()
        grown[1:] |= region[:-1]; grown[:-1] |= region[1:]; grown[:, 1:] |= region[:, :-1]; grown[:, :-1] |= region[:, 1:]
        grown &= mask
        if (grown == region).all(): return region
        region = grown


def keep_largest_blob(mask, step=4):
    """Largest 8-connected component of a boolean mask, labelled on a downsampled grid (fast enough in pure Python)."""
    h, w = mask.shape
    small = mask[: h - h % step, : w - w % step].reshape(h // step, step, w // step, step).any(axis=(1, 3))
    sh, sw = small.shape
    label = np.zeros((sh, sw), np.int32); sizes = {}; n = 0
    for y in range(sh):
        for x in range(sw):
            if not small[y, x] or label[y, x]: continue
            n += 1; stack = [(y, x)]; label[y, x] = n; cnt = 0
            while stack:
                cy, cx = stack.pop(); cnt += 1
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < sh and 0 <= nx < sw and small[ny, nx] and not label[ny, nx]:
                            label[ny, nx] = n; stack.append((ny, nx))
            sizes[n] = cnt
    if not sizes: return mask
    best = max(sizes, key=sizes.get)
    keep = np.kron(label == best, np.ones((step, step), bool))
    out = np.zeros_like(mask); out[: keep.shape[0], : keep.shape[1]] = keep
    return mask & out


def _erase_rows(alpha, rows):
    for (y0, y1) in rows:
        alpha[int(y0 * alpha.shape[0]):int(y1 * alpha.shape[0]), :] = 0


def clean_cutout(im, o, legacy_blob=False):
    """Bria cut-out -> cleaned, trimmed RGBA. Options: alphaCut (default 40); eraseRowsFull [[f0,f1],..] (fractions of
    the untrimmed 1024 px cut-out, the PoC's original eraseRows); eraseRows (fractions of the trimmed height);
    keepLargest (drop loose bits: coins, crumbs, shadow smears); eraseRect [[x0,y0,x1,y1],..] (fractions of the
    final trimmed box, for smears that touch the object); dropPale {below, maxSat, minLum} (removes pale,
    unsaturated pixels in the bottom band: painted ground smears). legacy_blob=True reproduces the PoC exactly
    (eraseRows on the untrimmed image, centre-blob instead of largest blob)."""
    im = im.convert("RGBA")
    a = np.array(im).astype(np.float32)
    alpha = a[..., 3]
    alpha[alpha < o.get("alphaCut", 40)] = 0
    _erase_rows(alpha, o.get("eraseRowsFull", []) + (o.get("eraseRows", []) if legacy_blob else []))
    a[..., 3] = alpha
    im = Image.fromarray(a.astype(np.uint8))
    im = im.crop(im.getbbox())
    a = np.array(im).astype(np.float32)
    alpha = a[..., 3]
    if not legacy_blob:
        _erase_rows(alpha, o.get("eraseRows", []))
    if o.get("keepLargest"):
        blob = keep_main_blob(alpha > 0) if legacy_blob else keep_largest_blob(alpha > 0)
        alpha[~blob] = 0
    a[..., 3] = alpha
    out = Image.fromarray(a.astype(np.uint8))
    out = out.crop(out.getbbox())
    if o.get("dropPale"):                                      # pale, unsaturated paint smear under the object
        dp = o["dropPale"]; a = np.array(out).astype(np.float32); h = a.shape[0]
        rgb = a[..., :3] / 255; mx, mn = rgb.max(-1), rgb.min(-1)
        sat = (mx - mn) / np.maximum(mx, 1e-3); lum = (mx + mn) / 2
        band = np.zeros(lum.shape, bool); band[int(dp.get("below", 0.75) * h):] = True
        kill = band & (sat < dp.get("maxSat", 0.22)) & (lum > dp.get("minLum", 0.7))
        a[..., 3][kill] = 0
        out = Image.fromarray(a.astype(np.uint8))
        if o.get("keepLargest"):
            al = np.array(out)[..., 3] > 0; a = np.array(out); a[..., 3][~keep_largest_blob(al)] = 0; out = Image.fromarray(a)
        out = out.crop(out.getbbox())
    if o.get("eraseRect"):                                     # fractions of the final trimmed box (what library_sheet shows)
        a = np.array(out); h, w = a.shape[:2]
        for (x0, y0, x1, y1) in o["eraseRect"]:
            a[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w), 3] = 0
        out = Image.fromarray(a); out = out.crop(out.getbbox())
    return out


def match_to_scene(im, bg, box, tint=0.18):
    """Tint and darken the object toward the scene around it so it doesn't 'pop'."""
    W, H = bg.size
    x, y, w, h = box
    pad = max(w, h)
    region = bg.crop((max(0, x - pad), max(0, y - pad), min(W, x + w + pad), min(H, y + h + pad))).convert("RGB")
    r = np.array(region).reshape(-1, 3).astype(np.float32)
    mean = r.mean(0)
    lum_scene = (0.299 * mean[0] + 0.587 * mean[1] + 0.114 * mean[2]) / 255
    rgb = np.array(im).astype(np.float32)
    a = rgb[..., 3:4]
    col = rgb[..., :3]
    col = col * (1 - tint) + mean * tint
    col = col * (0.72 + 0.35 * lum_scene)
    gray = col.mean(-1, keepdims=True)
    col = gray + (col - gray) * 0.85
    out = Image.fromarray(np.concatenate([np.clip(col, 0, 255), a], -1).astype(np.uint8))
    return out.filter(ImageFilter.GaussianBlur(0.35))


def shadow_for(im, strength=0.38):
    a = im.split()[3]
    sh = Image.new("RGBA", im.size, (40, 25, 15, 0))
    sh.putalpha(a.point(lambda v: int(v * strength)))
    pad = 16
    canvas = Image.new("RGBA", (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
    canvas.alpha_composite(sh, (pad, pad))
    return canvas.filter(ImageFilter.GaussianBlur(5)), pad


def occluder_from_polygon(bg, poly, feather=6):
    """Scene pixels inside `poly` (list of [x, y] in background coords), with the top edge feathered over `feather` px.
    Returns (patch RGBA, (x0, y0))."""
    xs = [p[0] for p in poly]; ys = [p[1] for p in poly]
    x0, y0, x1, y1 = int(min(xs)), int(min(ys)) - feather, int(max(xs)) + 1, int(max(ys)) + 1
    patch = bg.crop((x0, y0, x1, y1)).convert("RGBA")
    m = Image.new("L", patch.size, 0)
    ImageDraw.Draw(m).polygon([(px - x0, py - y0 + feather) for px, py in poly], fill=255)
    # feather: vertical box blur of the hard mask -> soft top edge (like the PoC's gradient occluder)
    arr = np.array(m).astype(np.float32)
    soft = np.zeros_like(arr)
    for k in range(-feather, feather + 1):
        soft += np.roll(arr, k, axis=0)
    soft /= (2 * feather + 1)
    patch.putalpha(Image.fromarray(np.clip(soft, 0, 255).astype(np.uint8)))
    return patch, (x0, y0)
