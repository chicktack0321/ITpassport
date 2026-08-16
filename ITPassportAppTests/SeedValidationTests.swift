import XCTest
@testable import ITPassportApp

/// 同梱する問題データの検証。
///
/// `scripts/validate_seed.py` と同じ検査をテストからも実行する。CIでスクリプトを回すだけだと、
/// ローカルでシードを編集したときに気付けない。国家試験の対策アプリで解説が間違っていたり
/// 正解が引けなくなっていたりするのは致命的なので、ビルドの一部として落とす。
final class SeedValidationTests: XCTestCase {

    private struct SeedFile: Decodable {
        let version: Int
        let syllabusVersion: String
        let questions: [SeedEntry]
    }

    private struct SeedEntry: Decodable {
        let questionId: String
        let questionText: String
        let choices: [String: String]
        let correctChoice: String
        let explanation: String
        let choiceExplanations: [String: String]
        let field: String
        let midCategory: String
        let keywords: [String]?
        let difficulty: Int?
    }

    /// 設計仕様書 §12 で決めたレイアウト上限
    private let maxQuestionLength = 300
    private let maxChoiceLength = 120

    private var seed: SeedFile!

    override func setUpWithError() throws {
        // テストターゲットにも seed JSON をリソースとして含めてある（project.yml 参照）
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: AppConfig.seedResourceName, withExtension: "json") else {
            XCTFail("シードファイル \(AppConfig.seedResourceName).json がテストバンドルに含まれていません")
            return
        }
        seed = try JSONDecoder().decode(SeedFile.self, from: Data(contentsOf: url))
    }

    func testSeedIsNotEmpty() {
        XCTAssertGreaterThan(seed.questions.count, 0)
        XCTAssertGreaterThan(seed.version, 0)
        XCTAssertFalse(seed.syllabusVersion.isEmpty)
    }

    /// questionId は学習履歴のキーそのもの。重複すると片方の進捗が消える
    func testQuestionIdsAreUnique() {
        let ids = seed.questions.map(\.questionId)
        XCTAssertEqual(Set(ids).count, ids.count, "questionId が重複している")
    }

    /// `ITP_<中分類>_<4桁>` の形式で、IDの中分類と属性が一致していること。
    /// ずれると一覧の絞り込みと採番体系が食い違う。
    func testQuestionIdFormatMatchesMidCategory() {
        for question in seed.questions {
            let parts = question.questionId.split(separator: "_")
            XCTAssertEqual(parts.count, 3, "\(question.questionId): ITP_<中分類>_<4桁> の形式ではない")
            guard parts.count == 3 else { continue }

            XCTAssertEqual(String(parts[0]), "ITP", "\(question.questionId): 接頭辞が ITP ではない")
            XCTAssertEqual(
                String(parts[1]), question.midCategory,
                "\(question.questionId): IDの中分類が midCategory と一致しない"
            )
            XCTAssertEqual(parts[2].count, 4, "\(question.questionId): 連番が4桁ではない")
            XCTAssertNotNil(Int(parts[2]), "\(question.questionId): 連番が数値ではない")
        }
    }

    /// 分野と中分類の対応が Swift 側の `MidCategory.field` と一致していること
    func testFieldMatchesMidCategory() {
        for question in seed.questions {
            guard let midCategory = MidCategory(rawValue: question.midCategory) else {
                XCTFail("\(question.questionId): 未知の中分類 '\(question.midCategory)'")
                continue
            }
            XCTAssertEqual(
                question.field, midCategory.field.rawValue,
                "\(question.questionId): field が中分類の属する分野と一致しない"
            )
        }
    }

    func testChoicesAreCompleteAndDistinct() {
        let labels = Set(ChoiceLabel.allCases.map(\.rawValue))

        for question in seed.questions {
            XCTAssertEqual(
                Set(question.choices.keys), labels,
                "\(question.questionId): choices のキーが A/B/C/D の4つではない"
            )
            let texts = question.choices.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            XCTAssertFalse(texts.contains(where: \.isEmpty), "\(question.questionId): 空の選択肢がある")
            // 同じ文言の選択肢があると、正解を選んでも不正解になりうる
            XCTAssertEqual(
                Set(texts).count, texts.count,
                "\(question.questionId): 同じ文言の選択肢がある"
            )
            for (label, text) in question.choices {
                XCTAssertLessThanOrEqual(
                    text.count, maxChoiceLength,
                    "\(question.questionId): 選択肢 \(label) が\(maxChoiceLength)字を超えている"
                )
            }
        }
    }

    func testCorrectChoiceIsValid() {
        for question in seed.questions {
            XCTAssertNotNil(
                ChoiceLabel(rawValue: question.correctChoice),
                "\(question.questionId): correctChoice '\(question.correctChoice)' が A/B/C/D ではない"
            )
        }
    }

    /// 4つの選択肢すべてに解説があること。
    /// 誤答選択肢が指す用語の意味を知ることが4択問題の学習価値の半分を占めるため、
    /// 1本でも欠けると解説パネルが空欄のまま表示される。
    func testEveryChoiceHasExplanation() {
        let labels = Set(ChoiceLabel.allCases.map(\.rawValue))

        for question in seed.questions {
            XCTAssertEqual(
                Set(question.choiceExplanations.keys), labels,
                "\(question.questionId): choiceExplanations のキーが A/B/C/D の4つではない"
            )
            XCTAssertFalse(
                question.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(question.questionId): explanation が空"
            )
            for (label, text) in question.choiceExplanations {
                XCTAssertFalse(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(question.questionId): 選択肢 \(label) の解説が空"
                )
            }
        }
    }

    /// 解説の書き出しで正誤が判別できること。
    /// 崩れると、解説パネルで「どれが正解の説明か」を読み取れなくなる。
    func testExplanationsStartWithVerdict() {
        for question in seed.questions {
            for (label, text) in question.choiceExplanations {
                let expected = label == question.correctChoice ? "正解" : "不正解"
                XCTAssertTrue(
                    text.hasPrefix(expected),
                    "\(question.questionId): 選択肢 \(label) の解説が '\(expected)' で始まっていない"
                )
            }
        }
    }

    func testQuestionTextLengthIsWithinLayoutLimit() {
        for question in seed.questions {
            XCTAssertFalse(
                question.questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(question.questionId): questionText が空"
            )
            XCTAssertLessThanOrEqual(
                question.questionText.count, maxQuestionLength,
                "\(question.questionId): questionText が\(maxQuestionLength)字を超えている"
            )
        }
    }

    /// 同じ論点を二度出題していないことの最低限の検出
    func testQuestionTextsAreUnique() {
        let texts = seed.questions.map(\.questionText)
        XCTAssertEqual(Set(texts).count, texts.count, "同じ問題文が複数ある")
    }

    func testDifficultyIsValid() {
        for question in seed.questions {
            let difficulty = question.difficulty ?? QuestionDifficulty.standard.rawValue
            XCTAssertNotNil(
                QuestionDifficulty(rawValue: difficulty),
                "\(question.questionId): difficulty '\(difficulty)' が 1/2/3 ではない"
            )
        }
    }

    /// 無料で解ける問題が残っていること。
    /// 全問が応用（課金対象）になると、未購入の利用者は演習を1問も始められない。
    func testFreeTierHasQuestions() {
        let freeDifficulties = AccessRights.locked.availableDifficulties.map(\.rawValue)
        let freeCount = seed.questions.filter {
            freeDifficulties.contains($0.difficulty ?? QuestionDifficulty.standard.rawValue)
        }.count

        XCTAssertGreaterThan(freeCount, 0, "未購入でも出題できる問題が1問もない")
    }

    /// 3分野すべてに問題があること。ホームの分野別習熟度が成立しなくなる
    func testAllFieldsAreCovered() {
        let fields = Set(seed.questions.map(\.field))
        for field in ExamField.allCases {
            XCTAssertTrue(
                fields.contains(field.rawValue),
                "\(field.displayName) の問題が1問もない"
            )
        }
    }
}
