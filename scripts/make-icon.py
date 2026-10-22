#!/usr/bin/env python3
"""把设计稿图标做成 macOS 风格的圆角透明图标，并生成 iconset / icns / asset catalog。"""
import os
import subprocess
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "Design/AppIcon/AppIcon-1024.png")
ICONSET = os.path.join(ROOT, "Design/AppIcon/Jingli.iconset")
CATALOG = os.path.join(ROOT, "App/Jingli/Assets.xcassets/AppIcon.appiconset")
ICNS = os.path.join(ROOT, "Design/AppIcon/Jingli.icns")

CANVAS = 1024
ART = 824
MARGIN = (CANVAS - ART) // 2
RADIUS = 185


def rounded_mask(size: int, radius: int, scale: int = 4) -> Image.Image:
    big = size * scale
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (0, 0, big - 1, big - 1),
        radius=radius * scale,
        fill=255,
    )
    return mask.resize((size, size), Image.LANCZOS)


def main() -> None:
    art = Image.open(SOURCE).convert("RGBA").resize((ART, ART), Image.LANCZOS)
    art.putalpha(rounded_mask(ART, RADIUS))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(art, (MARGIN, MARGIN), art)
    canvas.save(os.path.join(ROOT, "Design/AppIcon/AppIcon-1024-masked.png"))

    os.makedirs(ICONSET, exist_ok=True)
    os.makedirs(CATALOG, exist_ok=True)

    sizes = [16, 32, 128, 256, 512]
    for size in sizes:
        for scale, suffix in ((1, ""), (2, "@2x")):
            pixels = size * scale
            image = canvas.resize((pixels, pixels), Image.LANCZOS)
            name = f"icon_{size}x{size}{suffix}.png"
            image.save(os.path.join(ICONSET, name))
            image.save(os.path.join(CATALOG, name))

    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", ICNS], check=True)
    print(f"generated {ICNS} and {CATALOG}")


if __name__ == "__main__":
    main()
