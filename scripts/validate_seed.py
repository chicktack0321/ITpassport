#!/usr/bin/env python3
"""問題シードJSONの機械検証。

AI生成の問題は人手レビューを通す前提だが、レビューで見落としやすい形式面の欠陥
（IDの重複、解説の欠落、分野と中分類の不一致など）は機械で確実に落とす。
CIとユニットテストの両方から呼ぶ。

使い方:
    python scripts/validate_seed.py [シードJSONのパス]
"""

import json
import re
import sys
from collections import Counter
from pathlib import Path

DEFAULT_SEED = Path(__file__).resolve().parent.parent / "ITPassportApp" / "Resources" / "question_master_seed.json"

# 中分類コード → 分野。Swift側の MidCategory.field と対応させること
MID_CATEGORIES = {
    "CORP": "strategy",
    "LEGAL": "strategy",
    "BSTRA": "strategy",
    "TSTRA": "strategy",
    "BIZIND": "strategy",
    "SYSSTRA": "strategy",
    "SYSPLAN": "strategy",
    "SYSDEV": "management",
    "DEVMGT": "management",
    "PROJMGT": "management",
    "SVCMGT": "management",
    "AUDIT": "management",
    "THEORY": "technology",
    "ALGO": "technology",
    "HWCOMP": "technology",
    "SYSCOMP": "technology",
    "SW": "technology",
    "HW": "technology",
    "DESIGN": "technology",
    "MEDIA": "technology",
    "DB": "technology",
    "NW": "technology",
    "SEC": "technology",
}

CHOICE_LABELS = ["A", "B", "C", "D"]
QUESTION_ID_PATTERN = re.compile(r"^ITP_([A-Z]+)_(\d{4})$")

# 本文の長さ上限。レイアウトが崩れない範囲として設計仕様書 §12 で決めた値
MAX_QUESTION_LENGTH = 300
MAX_CHOICE_LENGTH = 120


def validate(path: Path) -> list[str]:
    """検出したエラーの一覧を返す。空リストなら合格。"""
    errors: list[str] = []

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return [f"JSONとして読めません: {e}"]

    for key in ("version", "syllabusVersion", "questions"):
        if key not in data:
            errors.append(f"トップレベルに '{key}' がありません")
    if errors:
        return errors

    questions = data["questions"]
    if not isinstance(questions, list) or not questions:
        return ["'questions' が空、または配列ではありません"]

    seen_ids: set[str] = set()
    seen_texts: dict[str, str] = {}

    for i, q in enumerate(questions):
        where = f"[{i}] {q.get('questionId', '(IDなし)')}"

        qid = q.get("questionId", "")
        match = QUESTION_ID_PATTERN.match(qid)
        if not match:
            errors.append(f"{where}: questionId の形式が ITP_<中分類>_<4桁> ではありません")
        else:
            id_category = match.group(1)
            if id_category not in MID_CATEGORIES:
                errors.append(f"{where}: questionId の中分類 '{id_category}' は未知のコードです")
            elif id_category != q.get("midCategory"):
                # IDと属性がずれていると、一覧の絞り込みと採番体系が食い違う
                errors.append(
                    f"{where}: questionId の中分類 '{id_category}' が "
                    f"midCategory '{q.get('midCategory')}' と一致しません"
                )

        if qid in seen_ids:
            errors.append(f"{where}: questionId が重複しています")
        seen_ids.add(qid)

        text = (q.get("questionText") or "").strip()
        if not text:
            errors.append(f"{where}: questionText が空です")
        elif len(text) > MAX_QUESTION_LENGTH:
            errors.append(f"{where}: questionText が{MAX_QUESTION_LENGTH}字を超えています（{len(text)}字）")
        # 同じ論点を二度出題しないための最低限の検出。表記まで同一のものだけを拾う
        if text in seen_texts:
            errors.append(f"{where}: questionText が {seen_texts[text]} と重複しています")
        else:
            seen_texts[text] = qid

        mid = q.get("midCategory")
        field = q.get("field")
        if mid not in MID_CATEGORIES:
            errors.append(f"{where}: midCategory '{mid}' は未知のコードです")
        elif MID_CATEGORIES[mid] != field:
            errors.append(
                f"{where}: field '{field}' は midCategory '{mid}' の分野 "
                f"'{MID_CATEGORIES[mid]}' と一致しません"
            )

        choices = q.get("choices") or {}
        if sorted(choices.keys()) != CHOICE_LABELS:
            errors.append(f"{where}: choices のキーが A/B/C/D の4つではありません")
        else:
            for label in CHOICE_LABELS:
                choice = (choices[label] or "").strip()
                if not choice:
                    errors.append(f"{where}: 選択肢 {label} が空です")
                elif len(choice) > MAX_CHOICE_LENGTH:
                    errors.append(
                        f"{where}: 選択肢 {label} が{MAX_CHOICE_LENGTH}字を超えています（{len(choice)}字）"
                    )
            # 同じ文言の選択肢があると、正解を選んでも不正解になりうる
            texts = [c.strip() for c in choices.values()]
            if len(set(texts)) != len(texts):
                errors.append(f"{where}: 選択肢に同じ文言のものがあります")

        correct = q.get("correctChoice")
        if correct not in CHOICE_LABELS:
            errors.append(f"{where}: correctChoice '{correct}' が A/B/C/D ではありません")

        if not (q.get("explanation") or "").strip():
            errors.append(f"{where}: explanation が空です")

        explanations = q.get("choiceExplanations") or {}
        if sorted(explanations.keys()) != CHOICE_LABELS:
            errors.append(f"{where}: choiceExplanations のキーが A/B/C/D の4つではありません")
        else:
            for label in CHOICE_LABELS:
                body = (explanations[label] or "").strip()
                if not body:
                    errors.append(f"{where}: 選択肢 {label} の解説が空です")
                    continue
                # 誤答の解説が「なぜ違うか」から書き出されているかを機械的に担保する。
                # ここが崩れていると、解説パネルで正誤の区別がつかなくなる
                expected = "正解" if label == correct else "不正解"
                if not body.startswith(expected):
                    errors.append(
                        f"{where}: 選択肢 {label} の解説が '{expected}' で始まっていません"
                    )

        difficulty = q.get("difficulty", 2)
        if difficulty not in (1, 2, 3):
            errors.append(f"{where}: difficulty '{difficulty}' が 1/2/3 ではありません")

        keywords = q.get("keywords")
        if keywords is not None and not isinstance(keywords, list):
            errors.append(f"{where}: keywords が配列ではありません")

    return errors


def report_distribution(path: Path) -> None:
    """出題の偏りを目視で確認するための集計。エラーではないので警告としてのみ出す。"""
    data = json.loads(path.read_text(encoding="utf-8"))
    questions = data["questions"]

    by_field = Counter(q.get("field") for q in questions)
    by_difficulty = Counter(q.get("difficulty", 2) for q in questions)
    by_category = Counter(q.get("midCategory") for q in questions)
    by_answer = Counter(q.get("correctChoice") for q in questions)

    total = len(questions)
    print(f"収録問題数: {total}問（シードversion {data['version']} / シラバス {data['syllabusVersion']}）")

    print("\n分野別（本試験の比率は 35 : 20 : 45）:")
    for field, label in (("strategy", "ストラテジ系"), ("management", "マネジメント系"), ("technology", "テクノロジ系")):
        count = by_field.get(field, 0)
        print(f"  {label:<12} {count:>4}問 ({count / total * 100:5.1f}%)")

    print("\n難易度別（目安は 30 : 50 : 20）:")
    for level, label in ((1, "基礎"), (2, "標準"), (3, "応用")):
        count = by_difficulty.get(level, 0)
        print(f"  {label:<12} {count:>4}問 ({count / total * 100:5.1f}%)")

    # 正解の位置の偏り。アプリは出題時にシャッフルするため学習には影響しないが、
    # 偏りが大きいと作問時に正解を先に書く癖が出ている合図になる。
    # `scripts/rebalance_answers.py` でならせる。
    print("\n正解の位置（偏っていれば作問の癖の合図。均等が目安）:")
    line = "  " + "  ".join(f"{label}:{by_answer.get(label, 0):>3}" for label in CHOICE_LABELS)
    print(line)
    most = max(by_answer.values()) if by_answer else 0
    if total and most / total > 0.40:
        print(
            f"  警告: 特定の位置に{most / total * 100:.0f}%が集中しています。"
            "python scripts/rebalance_answers.py で平準化できます。"
        )

    print("\n中分類別:")
    missing = [c for c in MID_CATEGORIES if c not in by_category]
    for category, count in sorted(by_category.items()):
        print(f"  {category:<8} {count:>4}問")
    if missing:
        print(f"\n  未収録の中分類: {', '.join(sorted(missing))}")


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SEED
    if not path.exists():
        print(f"シードファイルが見つかりません: {path}", file=sys.stderr)
        return 1

    errors = validate(path)
    if errors:
        print(f"検証に失敗しました（{len(errors)}件）:\n", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(f"検証に合格しました: {path}\n")
    report_distribution(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
