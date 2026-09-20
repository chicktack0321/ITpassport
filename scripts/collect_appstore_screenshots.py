"""UIテストが撮った画像から、App Store Connect に載せる5枚を選び出す。

    python scripts/collect_appstore_screenshots.py <xcparseの出力先> <保存先>

UIテストは画面の確認用に十数枚撮る（情報シートや途中の状態も含む）。
そのうち「アプリを説明するのに向いた5枚」だけを、並べたい順に番号を付け直して取り出す。

App Store Connect は画素数が決まっている（iPhone 6.9インチは 1320x2868 か 1290x2796）。
違う機種で撮ると提出時に弾かれるため、ここで検査して早く気付けるようにする。
"""
import shutil
import struct
import sys
from pathlib import Path

# (xcparse が出力するファイル名の先頭, 保存するときの名前, 画面の説明)。並べたい順。
# ファイル名を英数字にしているのは、ZIPで受け取ったときに文字化けしないようにするため。
WANTED = [
    ("01_Home", "1_home", "ホーム（習熟度）"),
    ("03_Quiz_Question", "2_quiz", "演習の出題"),
    ("04_Quiz_Explanation", "3_explanation", "全選択肢の解説"),
    ("05_QuestionList", "4_question_list", "問題一覧"),
    ("07_StudyHistory", "5_history", "学習履歴"),
]

# App Store Connect が受け付ける iPhone 6.9インチの画素数（縦向き）
ALLOWED_SIZES = {(1320, 2868), (1290, 2796)}


def png_size(path: Path) -> tuple[int, int]:
    """PNGのヘッダから幅と高さを読む。画像ライブラリに依存させないため自前で読む。"""
    with path.open("rb") as f:
        header = f.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"PNGではありません: {path}")
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def main() -> int:
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    destination.mkdir(parents=True, exist_ok=True)

    missing: list[str] = []
    sizes: set[tuple[int, int]] = set()

    for prefix, name, description in WANTED:
        # xcparse はファイル名の後ろに連番やUUIDを付けるため、前方一致で探す
        candidates = sorted(p for p in source.glob(f"{prefix}*.png"))
        if not candidates:
            missing.append(prefix)
            continue
        picked = candidates[0]
        sizes.add(png_size(picked))
        shutil.copy2(picked, destination / f"{name}.png")
        width, height = png_size(picked)
        print(f"{name}.png  {width}x{height}  {description}")

    if missing:
        print(f"\n撮れていない画面があります: {', '.join(missing)}", file=sys.stderr)
        print("UIテストが途中で失敗している可能性があるため、生の画像も確認すること。", file=sys.stderr)
        return 1

    unexpected = sizes - ALLOWED_SIZES
    if unexpected:
        allowed = " または ".join(f"{w}x{h}" for w, h in sorted(ALLOWED_SIZES))
        print(
            f"\n画素数が App Store Connect の6.9インチ用と違います: "
            f"{', '.join(f'{w}x{h}' for w, h in sorted(unexpected))}（必要なのは {allowed}）",
            file=sys.stderr,
        )
        print("ワークフローの device 入力で、6.9インチのiPhoneを指定すること。", file=sys.stderr)
        return 1

    print(f"\n{len(WANTED)}枚をそろえました: {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
