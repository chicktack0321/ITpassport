"""ロゴ右上のバッジに文字を描き直す。

受け取った元画像（`itpassport-logo-original.png`）は、バッジの中に
「NO GLYPH」のプレースホルダが4つ並んだ状態だった。画像を書き出したときの
フォントが該当の文字を持っておらず、豆腐が焼き込まれている。
そのままアイコンにすると App Store にオレンジの箱が4つ並ぶ。

元画像を手で直すのではなくスクリプトにしてあるのは、バッジの文言は
あとから変わりうるため。文言を変えたいときは BADGE_TEXT を書き換えて
このスクリプトを流し、続けて `make_app_icon.py` を実行する。

使い方: python scripts/fix_logo_badge.py
必要なもの: Pillow
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs/assets/itpassport-logo-original.png"
OUT = ROOT / "docs/assets/itpassport-logo-source.png"

BADGE_TEXT = "試験対策"

# バッジの白い内側（黒い枠線の内側）。元画像を実測した値。文字はこの中央に置く。
BADGE_BOX = (473, 78, 969, 256)

# 消す範囲は豆腐が乗っている部分だけに限る。
# バッジの外形は角丸なので、内側の矩形をまるごと白で塗ると四隅の丸みが失われ、
# ただの長方形になってしまう（一度それで潰した）。
# 豆腐は実測で x 631..814 / y 124..235。余白を少し取っても角丸には届かない。
ERASE_BOX = (625, 118, 820, 241)

# 枠線と同じ黒。白地に黒はアイコンサイズまで縮んでも潰れにくい
TEXT_COLOR = (0, 0, 0)

# 内側に対して文字が占める割合。詰めすぎると枠線と干渉して読みにくくなる
WIDTH_RATIO = 0.90
HEIGHT_RATIO = 0.78

# 太めのゴシックから順に試す。元のロゴが太字なので細い書体だと浮く
FONT_CANDIDATES = [
    ("C:/Windows/Fonts/BIZ-UDGothicB.ttc", 0),
    ("C:/Windows/Fonts/meiryob.ttc", 0),
    ("C:/Windows/Fonts/YuGothB.ttc", 0),
    ("C:/Windows/Fonts/msgothic.ttc", 0),
]


def load_font(size):
    for path, index in FONT_CANDIDATES:
        if not Path(path).exists():
            continue
        try:
            return ImageFont.truetype(path, size, index=index)
        except OSError:
            continue
    return None


def fit_font_size(text, max_width, max_height):
    """指定の枠に収まる最大の文字サイズを二分探索で求める。

    書体ごとに同じ指定サイズでも実寸が違うため、決め打ちにせず実際の描画寸法で測る。
    """
    low, high = 8, max_height * 2
    best = low
    while low <= high:
        mid = (low + high) // 2
        font = load_font(mid)
        if font is None:
            return None, None
        left, top, right, bottom = font.getbbox(text)
        if right - left <= max_width and bottom - top <= max_height:
            best = mid
            low = mid + 1
        else:
            high = mid - 1
    return best, load_font(best)


def main():
    if not SRC.exists():
        print(f"error: 元画像が見つかりません: {SRC}", file=sys.stderr)
        return 1

    im = Image.open(SRC).convert("RGB")
    draw = ImageDraw.Draw(im)

    x0, y0, x1, y1 = BADGE_BOX
    width, height = x1 - x0, y1 - y0

    # 豆腐だけを消す。バッジの残りはもともと白なので、これで下地が揃う
    draw.rectangle(list(ERASE_BOX), fill=(255, 255, 255))

    size, font = fit_font_size(
        BADGE_TEXT,
        int(width * WIDTH_RATIO),
        int(height * HEIGHT_RATIO),
    )
    if font is None:
        print("error: 日本語フォントが見つかりません", file=sys.stderr)
        return 1

    # getbbox の原点は文字の描画基準であって左上ではない。
    # 実際の描画範囲を測ってから、その中心をバッジの中心に合わせる。
    left, top, right, bottom = font.getbbox(BADGE_TEXT)
    tx = x0 + (width - (right - left)) / 2 - left
    ty = y0 + (height - (bottom - top)) / 2 - top
    draw.text((tx, ty), BADGE_TEXT, font=font, fill=TEXT_COLOR)

    im.save(OUT, "PNG", optimize=True)
    print(f"バッジに「{BADGE_TEXT}」を描画（文字サイズ {size}px）")
    print(f"wrote {OUT.relative_to(ROOT)} {im.size} {im.mode}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
