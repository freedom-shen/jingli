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
CONTENT_THRESHOLD = 30


def content_bbox(image: Image.Image, threshold: int = CONTENT_THRESHOLD):
    gray = image.convert("L")
    mask = gray.point(lambda value: 255 if value > threshold else 0)
    return mask.getbbox()


def centered_art(source: Image.Image) -> Image.Image:
    """按非黑内容包围盒把素材移到画布中心，避免素材本身偏心。"""
    bbox = content_bbox(source)
    if not bbox:
        return source

    center_x = (bbox[0] + bbox[2]) / 2
    center_y = (bbox[1] + bbox[3]) / 2
    dx = round(CANVAS / 2 - center_x)
    dy = round(CANVAS / 2 - center_y)
    if dx == 0 and dy == 0:
        return source

    centered = Image.new("RGBA", source.size, (0, 0, 0, 255))
    centered.paste(source, (dx, dy))
    print(f"recentered artwork: shift=({dx:+d}, {dy:+d}) from bbox={bbox}")
    return centered


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
    source = centered_art(Image.open(SOURCE).convert("RGBA"))
    art = source.resize((ART, ART), Image.LANCZOS)
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
