"""Build icon.ico from a square-ish source image: centre on a transparent square, keep alpha.

usage: make_icon.py SOURCE_IMAGE [OUT.ico]
"""
import sys
from pathlib import Path
from PIL import Image

SIZES = [(16, 16), (32, 32), (48, 48), (256, 256)]


def main(src: Path, out: Path) -> None:
    img = Image.open(src).convert("RGBA")
    side = max(img.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(img, ((side - img.width) // 2, (side - img.height) // 2), img)
    square.save(out, format="ICO", sizes=SIZES)
    print(f"wrote {out}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).with_name("icon.ico")
    main(src, out)
