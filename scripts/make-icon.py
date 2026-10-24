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


def content_centroid(image: Image.Image, threshold: int = CONTENT_THRESHOLD):
    """亮度加权质心：比包围盒更接近人眼感知的视觉重心（底部反光会拉偏包围盒）。"""
    gray = image.convert("L")
    pixels = gray.load()
    total = 0.0
    sum_x = 0.0
    sum_y = 0.0
    for y in range(gray.height):
        for x in range(gray.width):
            value = pixels[x, y]
            if value > threshold:
                total += value
                sum_x += x * value
                sum_y += y * value
    if total == 0:
        return None
    return sum_x / total, sum_y / total


def centered_art(source: Image.Image) -> Image.Image:
    """按内容视觉重心把素材移到画布中心，避免素材本身偏心。"""
    centroid = content_centroid(source)
    if not centroid:
        return source

    center_x, center_y = centroid
    dx = round(CANVAS / 2 - center_x)
    dy = round(CANVAS / 2 - center_y)
    if dx == 0 and dy == 0:
        return source

    centered = Image.new("RGBA", source.size, (0, 0, 0, 255))
    centered.paste(source, (dx, dy))
    print(f"recentered artwork: shift=({dx:+d}, {dy:+d}) from centroid=({center_x:.1f}, {center_y:.1f})")
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
