"""作問バッチをシードへ取り込む。

設計仕様書 §9.2 のとおり、`questionId` は作問時には振らず、ここで採番する。
AIに採番させると、バッチをまたいだ連番の管理ができず衝突する。

バッチファイルは questionId を持たない問題の配列（作問プロンプトの出力形式そのまま）。

    python scripts/merge_questions.py batches/sec-01.json [batches/nw-01.json ...]

やること:
  - 中分類ごとに既存の最大連番の続きから採番する
  - 問題文が既存と重複していれば取り込まずに報告する
  - シードの version を1つ上げる（アプリ更新時にUpsertを走らせるため）

取り込み後は必ず `python scripts/validate_seed.py` を通すこと。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "ITPassportApp" / "Resources" / "question_master_seed.json"

QUESTION_ID_PATTERN = re.compile(r"^ITP_([A-Z]+)_(\d{4})$")


def next_numbers(questions):
    """中分類ごとの次の連番を求める。

    欠番は埋めない。取り下げた問題のIDを再利用すると、その問題を解いた人の
    学習履歴が別の問題に引き継がれてしまう。
    """
    highest = {}
    for q in questions:
        match = QUESTION_ID_PATTERN.match(q.get("questionId", ""))
        if not match:
            continue
        category, number = match.group(1), int(match.group(2))
        highest[category] = max(highest.get(category, 0), number)
    return {category: number + 1 for category, number in highest.items()}


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1

    seed = json.loads(SEED.read_text(encoding="utf-8"))
    questions = seed["questions"]

    counters = next_numbers(questions)
    existing_texts = {q["questionText"].strip(): q["questionId"] for q in questions}

    added = 0
    skipped = []

    for path in sys.argv[1:]:
        batch = json.loads(Path(path).read_text(encoding="utf-8"))
        for entry in batch:
            category = entry.get("midCategory")
            if not category:
                skipped.append((path, entry.get("questionText", "")[:30], "midCategory がない"))
                continue

            text = entry["questionText"].strip()
            if text in existing_texts:
                skipped.append((path, text[:30], f"問題文が {existing_texts[text]} と重複"))
                continue

            number = counters.get(category, 1)
            counters[category] = number + 1

            # 取り込み順ではなくキー順を揃えておくと、後から差分を読むときに追いやすい
            merged = {"questionId": f"ITP_{category}_{number:04d}"}
            merged.update(entry)
            questions.append(merged)
            existing_texts[text] = merged["questionId"]
            added += 1

    if added == 0:
        print("取り込む問題がありませんでした")
    else:
        # 一覧の並びは questionId 順。中分類ごとにまとまって読みやすくなる
        questions.sort(key=lambda q: q["questionId"])
        seed["version"] += 1
        SEED.write_text(
            json.dumps(seed, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"{added}問を取り込みました（合計 {len(questions)}問 / version {seed['version']}）")

    for path, text, reason in skipped:
        print(f"  スキップ [{Path(path).name}] {text}… — {reason}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
