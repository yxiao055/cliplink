from pathlib import Path

from PIL import Image, ImageDraw

INK = (16, 35, 29, 255)
LIME = (217, 255, 120, 255)
CORAL = (255, 108, 78, 255)
PAPER = (252, 250, 244, 255)
SIZE = 1024


def rounded_rect(size, radius, color):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=color)
    return layer


def draw_card(base, center, size, color, line_color, angle):
    w, h = size
    card = rounded_rect((w, h), int(w * 0.17), color)
    d = ImageDraw.Draw(card)
    for i in range(3):
        y = int(h * (0.33 + i * 0.16))
        inset = int(w * (0.16 + i * 0.03))
        right_inset = int(w * (i * 0.08 + 0.14))
        d.line((inset, y, w - right_inset, y), fill=line_color, width=max(6, int(w * 0.045)))
    rotated = card.rotate(angle, expand=True, resample=Image.Resampling.BICUBIC)
    left = int(center[0] - rotated.width / 2)
    top = int(center[1] - rotated.height / 2)
    base.alpha_composite(rotated, (left, top))


def icon(foreground=False):
    if foreground:
        img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        scale = 1.05
    else:
        img = Image.new("RGBA", (SIZE, SIZE), INK)
        scale = 0.88

    # soft halo
    halo = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hd.ellipse((180, 180, 880, 880), fill=(217, 255, 120, 28))
    img.alpha_composite(halo)

    card_w = int(350 * scale)
    card_h = int(460 * scale)
    draw_card(
        img,
        (int(SIZE * 0.415), int(SIZE * 0.435)),
        (card_w, card_h),
        LIME,
        (16, 35, 29, 180),
        -11,
    )
    draw_card(
        img,
        (int(SIZE * 0.60), int(SIZE * 0.585)),
        (card_w, card_h),
        CORAL,
        (16, 35, 29, 200),
        12,
    )

    return img


out = Path(__file__).resolve().parent.parent / "assets" / "branding"
out.mkdir(parents=True, exist_ok=True)
icon(False).save(out / "app_icon.png")
icon(True).save(out / "app_icon_foreground.png")
print(f"icons generated in {out}")
