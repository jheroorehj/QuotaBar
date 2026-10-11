#!/usr/bin/env python3
"""앱 아이콘(AppIcon.icns)을 만든다. 필요: Pillow, numpy, iconutil(macOS).

    python3 scripts/make-app-icon.py

메뉴바용 단색 글리프(Sources/Icons/icons_QuotaBar.icns)를 검은 유리 판 위에 올리고
유리 광택·테두리 반사와 글리프의 두께·그림자를 넣어 입체감을 준다. 메뉴바 아이콘은 그대로 둔다.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "Sources" / "Icons"
S = 1024            # 작업 캔버스
PLATE = 824         # macOS 아이콘 격자: 1024 안에 824 판
DEPTH = 16          # 글리프 두께(px)


def glyph_alpha() -> Image.Image:
    """메뉴바 아이콘에서 가장 큰 그림의 알파만 꺼낸다."""
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "g.iconset"
        subprocess.run(["iconutil", "-c", "iconset", str(ICONS / "icons_QuotaBar.icns"), "-o", str(out)], check=True)
        alpha = Image.open(out / "icon_512x512@2x.png").convert("RGBA").getchannel("A")
    return alpha.crop(alpha.getbbox())


def squircle(size: int, n: float = 5.0) -> Image.Image:
    """연속 곡률 둥근 사각형(초타원) 마스크. 4배로 그려 줄여서 가장자리를 다듬는다."""
    big = size * 4
    axis = np.linspace(-1, 1, big)
    x, y = np.meshgrid(axis, axis)
    inside = (np.abs(x) ** n + np.abs(y) ** n) <= 1
    return Image.fromarray((inside * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)


def vertical_gradient(size, top, bottom) -> Image.Image:
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    rows = np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t
    return Image.fromarray(np.broadcast_to(rows, (h, w, 3)).astype(np.uint8), "RGB")


def tinted(alpha: Image.Image, color, opacity: float = 1.0) -> Image.Image:
    layer = Image.new("RGBA", alpha.size, tuple(color) + (0,))
    layer.putalpha(alpha.point(lambda v: int(v * opacity)))
    return layer


def placed(alpha: Image.Image, origin) -> Image.Image:
    canvas = Image.new("L", (S, S), 0)
    canvas.paste(alpha, origin)
    return canvas


def shifted(alpha: Image.Image, dx: int, dy: int) -> Image.Image:
    return ImageChops.offset(alpha, dx, dy)


def build() -> Image.Image:
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inset = (S - PLATE) // 2
    plate = placed(squircle(PLATE), (inset, inset))

    # 판 아래 그림자
    icon.alpha_composite(tinted(shifted(plate, 0, 14).filter(ImageFilter.GaussianBlur(16)), (0, 0, 0), 0.42))

    # 판: 검은 유리. 위는 짙은 회색, 아래는 거의 검정.
    body = vertical_gradient((S, S), (50, 52, 58), (4, 4, 6)).convert("RGBA")
    yy, xx = np.mgrid[0:S, 0:S]
    # 아래쪽에 비쳐 올라오는 옅은 빛 (유리 속 깊이감)
    floor = np.clip(1 - np.hypot((xx - S * 0.5) / 1.5, yy - S * 0.98) / (S * 0.34), 0, 1) ** 2
    body.alpha_composite(tinted(Image.fromarray((floor * 255).astype(np.uint8)), (150, 165, 200), 0.22))
    # 윗부분을 덮는 유리 광택: 큰 타원의 아랫자락이 판 위쪽 절반에 걸치고, 아래로 갈수록 옅어진다.
    ellipse = ((xx - S * 0.5) / (PLATE * 0.95)) ** 2 + ((yy - (inset - PLATE * 0.42)) / (PLATE * 0.92)) ** 2
    fade = np.clip(1 - (yy - inset) / (PLATE * 0.52), 0, 1)
    gloss = np.clip((1 - ellipse) * 40, 0, 1) * (0.25 + 0.75 * fade)
    body.alpha_composite(tinted(Image.fromarray((gloss * 255).astype(np.uint8)), (255, 255, 255), 0.17))
    body.putalpha(plate)
    icon.alpha_composite(body)

    # 유리 테두리: 둘레 전체에 가는 반사선, 위쪽은 더 밝게, 아래쪽 안쪽은 어둡게
    ring = ImageChops.subtract(plate, plate.filter(ImageFilter.MinFilter(7))).filter(ImageFilter.GaussianBlur(0.8))
    top_rim = ImageChops.subtract(plate, shifted(plate, 0, 5)).filter(ImageFilter.GaussianBlur(1.2))
    bottom_rim = ImageChops.subtract(plate, shifted(plate, 0, -7)).filter(ImageFilter.GaussianBlur(2.5))
    icon.alpha_composite(tinted(bottom_rim, (0, 0, 0), 0.5))
    icon.alpha_composite(tinted(ring, (255, 255, 255), 0.16))
    icon.alpha_composite(tinted(top_rim, (255, 255, 255), 0.6))

    # 글리프: 판 너비의 62%, 꼬리(오른쪽 아래) 무게를 감안해 살짝 왼쪽 위로
    glyph = glyph_alpha()
    width = int(PLATE * 0.62)
    glyph = glyph.resize((width, round(glyph.height * width / glyph.width)), Image.LANCZOS)
    origin = ((S - glyph.width) // 2 - 6, (S - glyph.height) // 2 - DEPTH // 2 - 4)
    face = placed(glyph, origin)
    clip = lambda layer_alpha: ImageChops.multiply(layer_alpha, plate)

    # 바닥에 떨어지는 그림자 (넓고 옅은 것 + 좁고 진한 것)
    icon.alpha_composite(tinted(clip(shifted(face, 0, DEPTH + 30).filter(ImageFilter.GaussianBlur(26))), (0, 0, 8), 0.55))
    icon.alpha_composite(tinted(clip(shifted(face, 0, DEPTH + 8).filter(ImageFilter.GaussianBlur(7))), (0, 0, 8), 0.50))

    # 옆면(두께): 아래로 갈수록 어두워지는 층을 쌓는다
    for step in range(DEPTH, 0, -1):
        t = step / DEPTH
        side = tuple(int(a * (1 - t) + b * t) for a, b in zip((176, 180, 190), (74, 77, 86)))
        icon.alpha_composite(tinted(shifted(face, 0, step), side))

    # 윗면: 흰색 → 옅은 푸른 회색
    top = vertical_gradient((S, S), (255, 255, 255), (218, 222, 230)).convert("RGBA")
    top.putalpha(face)
    icon.alpha_composite(top)
    # 윗면 위쪽 모서리의 밝은 선
    edge = ImageChops.subtract(face, shifted(face, 0, 3)).filter(ImageFilter.GaussianBlur(0.8))
    icon.alpha_composite(tinted(edge, (255, 255, 255), 0.9))
    return icon


def main() -> None:
    icon = build()
    # 인자로 경로를 주면 1024px 미리보기 PNG 도 저장한다.
    if len(sys.argv) > 1:
        icon.save(sys.argv[1])
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
                icon.resize((points * scale,) * 2, Image.LANCZOS).save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICONS / "AppIcon.icns")], check=True)
    print(f"✔ {ICONS / 'AppIcon.icns'}")


if __name__ == "__main__":
    main()
