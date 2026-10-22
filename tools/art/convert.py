#!/usr/bin/env python3
"""Art pipeline: AI-generated PNG (magenta #FF00FF background) -> WoW-ready power-of-two TGA.

usage: convert.py manifest.json [--only NAME ...] [--out DIR]
Manifest entries: {"name", "src", "size": [w, h], "mode": "key" | "tile" | "opaque", "out": "dir"}
  key    : magenta keyed to alpha with despill (or the PNG's own alpha if it has one),
           trimmed, fit into size (aspect kept, centered)
  tile   : seamless background, no keying, resized to size; writes a 2x2 preview to check seams
  opaque : no keying, cover-crop to size (portraits)
Also writes <out>/_preview/<name>.png on a dark plate for eyeballing at real display size.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops

MAGENTA = (255, 0, 255)
PLATE = (20, 15, 11)  # DESIGN.md stone-1, the color the art sits on in game


def is_pow2(n: int) -> bool:
    return n > 0 and n & (n - 1) == 0


def key_magenta(im: Image.Image) -> Image.Image:
    """Alpha from 'magenta-ness' (min(R,B) - G), then un-blend the magenta fringe out of edge colors."""
    r, g, b = im.convert("RGB").split()
    # m = how much of the pixel is magenta, 0..255; 255 = pure background
    m = ImageChops.subtract(ImageChops.darker(r, b), g)
    alpha = m.point(lambda v: 0 if v > 200 else (255 if v < 60 else int(255 * (200 - v) / 140)))
    rgba = Image.merge("RGBA", (r, g, b, alpha))
    px = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            cr, cg, cb, a = px[x, y]
            if 0 < a < 255:
                k = a / 255
                # observed = k*fg + (1-k)*magenta  ->  fg = (observed - (1-k)*magenta) / k
                px[x, y] = (
                    max(0, min(255, int((cr - (1 - k) * 255) / k))),
                    max(0, min(255, int(cg / k))),
                    max(0, min(255, int((cb - (1 - k) * 255) / k))),
                    a,
                )
    return rgba


def fit(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    im.thumbnail(size, Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(im, ((size[0] - im.width) // 2, (size[1] - im.height) // 2), im)
    return canvas


def cover(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = max(size[0] / im.width, size[1] / im.height)
    im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    left, top = (im.width - size[0]) // 2, (im.height - size[1]) // 2
    return im.crop((left, top, left + size[0], top + size[1])).convert("RGBA")


def preview(im: Image.Image, path: Path, tile: bool) -> None:
    if tile:
        sheet = Image.new("RGBA", (im.width * 2, im.height * 2))
        for dx in (0, im.width):
            for dy in (0, im.height):
                sheet.paste(im, (dx, dy))
        im = sheet
    plate = Image.new("RGBA", im.size, PLATE + (255,))
    plate.alpha_composite(im)
    path.parent.mkdir(parents=True, exist_ok=True)
    plate.convert("RGB").save(path)


def convert(entry: dict, base: Path) -> Path:
    size = tuple(entry["size"])
    if not all(is_pow2(n) for n in size):
        raise ValueError(f"{entry['name']}: size {size} must be powers of two for WoW")
    src = Image.open(base / entry["src"])
    mode = entry.get("mode", "key")
    if mode == "key":
        has_alpha = src.mode in ("RGBA", "LA") and src.getchannel("A").getextrema()[0] < 255
        out = fit(src.convert("RGBA") if has_alpha else key_magenta(src), size)
    elif mode == "tile":
        out = src.convert("RGBA").resize(size, Image.LANCZOS)
    elif mode == "opaque":
        out = cover(src, size)
    else:
        raise ValueError(f"{entry['name']}: unknown mode {mode}")
    out_dir = base / entry["out"]
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / f"{entry['name']}.tga"
    out.save(dest)  # uncompressed 32-bit TGA, the uncompressed 32-bit TGA format WoW reads reliably
    preview(out, out_dir / "_preview" / f"{entry['name']}.png", mode == "tile")
    return dest


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--only", nargs="+", help="convert just these names")
    ap.add_argument("--out", help="override every entry's out dir (relative to the manifest)")
    args = ap.parse_args()
    manifest = args.manifest.resolve()
    missing = 0
    for entry in json.loads(manifest.read_text()):
        if args.only and entry["name"] not in args.only:
            continue
        if args.out:
            entry = {**entry, "out": args.out}
        if not (manifest.parent / entry["src"]).exists():
            missing += 1
            continue
        try:
            print("ok  ", convert(entry, manifest.parent))
        except (OSError, ValueError) as e:
            print("FAIL", entry["name"], e)
    if missing:
        print(f"skipped {missing} entries whose source PNG does not exist yet")


if __name__ == "__main__":
    main()
