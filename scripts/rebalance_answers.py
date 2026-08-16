"""シード内で正解の選択肢が偏っているのをならす。

作問では「正しい説明」を最初に思い付いて書くため、正解がAに寄りやすい。
実測で300問中225問がAだった。

アプリは出題時に選択肢を毎回シャッフルする（`QuizViewModel.buildQuestion`）ので、
利用者の学習には影響しない。それでも直すのは、シードを人がレビューするときに
偏りが目に付き、作問の質そのものを疑わせるため。また将来シャッフルを外した場合に
そのまま欠陥になる。

やること: 各問題について、正解の位置が A→B→C→D と順に巡るよう、
正解の選択肢と目標位置の選択肢を入れ替える。入替えは本文と解説を対にして動かすので、
問題の意味は変わらない。

前提: 解説の本文が選択肢の記号（「選択肢Aは〜」など）に言及していないこと。
言及があると入替えで内容が破綻する。実行前に検査し、見つかれば中止する。

    python scripts/rebalance_answers.py
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "ITPassportApp" / "Resources" / "question_master_seed.json"

LABELS = ["A", "B", "C", "D"]

# 「選択肢A」のように記号を指して説明している箇所を見つけるための検査。
# 入替えの前提が崩れていないかを確かめる
LABEL_REFERENCE = re.compile(r"(選択肢[ABCD]|[ABCD]の選択肢|記号[ABCD])")


def find_label_references(question):
    texts = [question["questionText"], question["explanation"]]
    texts += list(question["choiceExplanations"].values())
    texts += list(question["choices"].values())
    return [m.group() for t in texts for m in LABEL_REFERENCE.finditer(t)]


def swap(question, a, b):
    """二つの選択肢の本文と解説を入れ替え、正解の記号を更新する。"""
    if a == b:
        return
    choices, explanations = question["choices"], question["choiceExplanations"]
    choices[a], choices[b] = choices[b], choices[a]
    explanations[a], explanations[b] = explanations[b], explanations[a]
    if question["correctChoice"] == a:
        question["correctChoice"] = b
    elif question["correctChoice"] == b:
        question["correctChoice"] = a


def main():
    seed = json.loads(SEED.read_text(encoding="utf-8"))
    questions = seed["questions"]

    blocked = [(q["questionId"], find_label_references(q)) for q in questions]
    blocked = [(qid, refs) for qid, refs in blocked if refs]
    if blocked:
        print("選択肢の記号に言及している問題があるため中止します:", file=sys.stderr)
        for qid, refs in blocked:
            print(f"  {qid}: {', '.join(refs)}", file=sys.stderr)
        return 1

    before = Counter(q["correctChoice"] for q in questions)

    # 中分類ごとに巡回させる。全体で通し番号にすると、
    # 一覧をquestionId順に見たとき同じ位置が連続して並ぶ
    counters = {}
    for question in questions:
        category = question["midCategoryRaw"] if "midCategoryRaw" in question else question["midCategory"]
        index = counters.get(category, 0)
        counters[category] = index + 1
        swap(question, question["correctChoice"], LABELS[index % len(LABELS)])

    after = Counter(q["correctChoice"] for q in questions)

    SEED.write_text(
        json.dumps(seed, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print("正解の分布を平準化しました")
    print(f"  変更前: {dict(sorted(before.items()))}")
    print(f"  変更後: {dict(sorted(after.items()))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
