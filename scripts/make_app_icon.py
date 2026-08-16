"""元画像からアプリアイコンとアプリ内ロゴを書き出す。

App Store のアイコンには決まりがある。
  - 1024x1024 の正方形
  - アルファチャンネルを持たない（透過があると審査で弾かれる）
  - 角丸を焼き込まない（Apple 側がマスクをかけるので、素材に角丸があると角に縁が残る）

アプリ内ロゴ（AppLogo）も同じ素材から作る。こちらは cornerRadius: 10 の浅いクリップなので、
角丸なしの正方形でないと角の残りがそのまま見える。

書き出し用に画像を整えるだけの処理を置く場所であって、絵柄そのものは扱わない。
文字や配色を変えたいときは元画像（`docs/assets/itpassport-logo-source.png`）を直すこと。

使い方: リポジトリのどこからでも `python scripts/make_app_icon.py`
必要なもの: Pillow
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs/assets/itpassport-logo-source.png"
ASSETS = ROOT / "ITPassportApp/Resources/Assets.xcassets"
OUT_ICON = ASSETS / "AppIcon.appiconset/AppIcon-1024.png"
OUT_LOGO_DIR = ASSETS / "AppLogo.imageset"

LOGO_SIZES = [("AppLogo.png", 80), ("AppLogo@2x.png", 160), ("AppLogo@3x.png", 240)]

# これ以上明るければ「白」とみなす。書き出しツールが付けた余白の判定に使う
WHITE_LEVEL = 245

# 端の行・列が内側よりこれだけ明るければ、白との境目の中間色とみなして削る
EDGE_BLEND_DELTA = 8

# 角がこれより明るければ、角丸の外側の余白が焼き込まれていると判断する
LIGHT_CORNER = 150

# iOSのアイコンマスクの角丸半径（辺の長さに対する比）
MASK_RADIUS_RATIO = 0.2237
# 背景と違うとみなす色の差（RGB各成分の差の合計）
CONTENT_DELTA = 40


def trim_white_margin(im):
    """完全に白い帯を落とす。

    書き出しツールによっては絵柄が版面の中央に来ず、辺のどれかに白い帯が残る。
    受け取った元画像は左に26px、下に15pxの帯があり、上と右は端まで塗られていた。
    この状態でアイコンにすると、Apple のマスクをかけたあとに左下だけ白い縁が出る。

    絵柄自体にも白は使われている（"IT パスポート" の文字やバッジ）ため、
    画素単位ではなく「その行・列がすべて白かどうか」で判定する。
    """
    px = im.load()
    w, h = im.size

    def row_is_white(y):
        return all(min(px[x, y]) > WHITE_LEVEL for x in range(0, w, 2))

    def col_is_white(x):
        return all(min(px[x, y]) > WHITE_LEVEL for y in range(0, h, 2))

    top = 0
    while top < h and row_is_white(top):
        top += 1
    bottom = h - 1
    while bottom > top and row_is_white(bottom):
        bottom -= 1
    left = 0
    while left < w and col_is_white(left):
        left += 1
    right = w - 1
    while right > left and col_is_white(right):
        right -= 1

    if (left, top, right, bottom) == (0, 0, w - 1, h - 1):
        return im

    # 白との境目には中間色が1px残る（実測で (255,255,255) の隣が (126,128,229)、
    # 地色は (53,56,214)）。この1列は `fit_inside_mask` が余白を作るときに
    # 引き伸ばされるため、そのまま残すとアイコンの端に明るい帯となって出る。
    # 内側と明るさが揃うまで削る。
    def mean(line):
        return sum(sum(px[x, y]) for x, y in line) / (3 * len(line))

    def row(y):
        return [(x, y) for x in range(left, right + 1, 2)]

    def col(x):
        return [(x, y) for y in range(top, bottom + 1, 2)]

    while top < bottom - 2 and mean(row(top)) - mean(row(top + 2)) > EDGE_BLEND_DELTA:
        top += 1
    while bottom > top + 2 and mean(row(bottom)) - mean(row(bottom - 2)) > EDGE_BLEND_DELTA:
        bottom -= 1
    while left < right - 2 and mean(col(left)) - mean(col(left + 2)) > EDGE_BLEND_DELTA:
        left += 1
    while right > left + 2 and mean(col(right)) - mean(col(right - 2)) > EDGE_BLEND_DELTA:
        right -= 1

    print(f"白い帯と境界を除去: 左{left} 右{w - 1 - right} 上{top} 下{h - 1 - bottom}")
    return im.crop((left, top, right + 1, bottom + 1))


def crop_to_square(im):
    """中央から最大の正方形を切り出す。

    比率を変えて引き伸ばすと文字が微妙に歪む。数%の違いなら切り落としたほうが目立たない。
    """
    w, h = im.size
    if w == h:
        return im
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    print(f"正方形に切り出し: {w}x{h} -> {side}x{side}")
    return im.crop((left, top, left + side, top + side))


def check_full_bleed(im):
    """角丸が焼き込まれた素材を黙って通さないための確認。

    余白つきの素材をそのまま使うと、Apple のマスクをかけたあとに角へ縁が残る。
    見落とすとビルドを上げ直すことになるので、ここで気付けるようにしておく。
    """
    px = im.load()
    w, h = im.size
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    light = [c for c in corners if min(c[:3]) > LIGHT_CORNER]
    if light:
        print(
            f"warning: 角が明るい {light}。角丸と余白が焼き込まれている可能性がある。"
            "Apple のマスク後に角へ縁が残るので、端まで塗った正方形にしてから使うこと。",
            file=sys.stderr,
        )


def content_points(im, step=2):
    """背景と違う色の画素（＝絵柄）を拾う。

    背景は上端から下端への縦グラデーションとみなし、行ごとの基準色と比べる。
    """
    px = im.load()
    size = im.size[0]
    top, bottom = px[0, 0], px[0, size - 1]

    def background(y):
        t = y / (size - 1)
        return [top[i] + (bottom[i] - top[i]) * t for i in range(3)]

    points = []
    for y in range(0, size, step):
        base = background(y)
        for x in range(0, size, step):
            pixel = px[x, y]
            if sum(abs(pixel[i] - base[i]) for i in range(3)) > CONTENT_DELTA:
                points.append((x, y))
    return points


def required_scale(im):
    """絵柄がマスクの内側に収まる縮小率を求める。1.0 なら調整不要。"""
    size = im.size[0]
    radius = MASK_RADIUS_RATIO * size
    center = (size - 1) / 2
    points = content_points(im)

    def inside(x, y):
        cx = min(max(x, radius), size - 1 - radius)
        cy = min(max(y, radius), size - 1 - radius)
        return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2

    scale = 1.0
    while scale > 0.80:
        if all(inside(center + (x - center) * scale, center + (y - center) * scale) for x, y in points):
            return scale
        scale -= 0.005
    return scale


def fit_inside_mask(im):
    """Apple の角丸マスクに絵柄が掛からないよう、必要なぶんだけ縮めて余白を足す。

    素材が端まで塗られていても、角に近い絵柄はマスクで切り落とされる。
    増やした余白は端の行・列を引き伸ばして埋めるので、背景の見た目は変わらない。
    """
    scale = required_scale(im)
    if scale >= 1.0:
        print("絵柄はマスクの内側に収まっている")
        return im

    size = im.size[0]
    inner = round(size * scale)
    offset = (size - inner) // 2
    print(f"マスクに掛かるため {scale:.3f} 倍に縮め、周囲に {offset}px の余白を足す")

    scaled = im.resize((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGB", (size, size))
    canvas.paste(scaled, (offset, offset))

    # 上下を端の行で、そのあと左右を端の列で埋める（角も自然に埋まる）
    bottom_band = size - offset - inner
    if offset > 0:
        canvas.paste(scaled.crop((0, 0, inner, 1)).resize((inner, offset)), (offset, 0))
    if bottom_band > 0:
        canvas.paste(
            scaled.crop((0, inner - 1, inner, inner)).resize((inner, bottom_band)),
            (offset, offset + inner)
        )
    if offset > 0:
        canvas.paste(canvas.crop((offset, 0, offset + 1, size)).resize((offset, size)), (0, 0))
    right_band = size - offset - inner
    if right_band > 0:
        canvas.paste(
            canvas.crop((offset + inner - 1, 0, offset + inner, size)).resize((right_band, size)),
            (offset + inner, 0)
        )
    return canvas


def main():
    if not SRC.exists():
        print(f"error: 元画像が見つかりません: {SRC}", file=sys.stderr)
        return 1

    src = Image.open(SRC)
    print(f"source: {SRC.name} {src.size} {src.mode}")

    # パレットや透過つきで渡されても、書き出しは必ずアルファなしのRGBにする
    src = src.convert("RGB")
    src = trim_white_margin(src)
    src = crop_to_square(src)
    check_full_bleed(src)
    src = fit_inside_mask(src)

    icon = src if src.size == (1024, 1024) else src.resize((1024, 1024), Image.LANCZOS)
    icon.save(OUT_ICON, "PNG", optimize=True)
    print(f"wrote {OUT_ICON.name} {icon.size} {icon.mode}")

    for name, size in LOGO_SIZES:
        src.resize((size, size), Image.LANCZOS).save(OUT_LOGO_DIR / name, "PNG", optimize=True)
        print(f"wrote {name} {size}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
