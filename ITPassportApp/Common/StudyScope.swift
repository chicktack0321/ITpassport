import Foundation

/// 出題・集計の対象範囲。
///
/// 演習の出題範囲と、ホームの習熟度の内訳で共有する。
/// 全問をひとまとめに扱うと習熟度のバーはほとんど動かず、出題も分野が散らばって
/// 「いま何を潰しているのか」が分からなくなる。範囲を狭められること自体が機能。
struct StudyScope: Equatable, Codable {
    /// nil は「全分野」。中分類を選んだ場合は、そちらが分野を含意する
    var field: ExamField?
    /// nil は「その分野のすべて」
    var midCategory: MidCategory?
    /// nil は「すべての難易度」（権利の範囲内）
    var difficulty: QuestionDifficulty?

    static let `default` = StudyScope()

    /// 難易度を指定していないときに出題する範囲。
    ///
    /// 英単語版では既習の基礎語彙を既定から外していたが、こちらは外さない。
    /// 用語の定義を問う基礎問題は本試験でも実際に出題され、飛ばす理由がないため。
    static let studyDefaultDifficulties: Set<QuestionDifficulty> = Set(QuestionDifficulty.allCases)
    /// 習熟度の集計で「すべて」を選んだときの範囲
    static let allDifficulties: Set<QuestionDifficulty> = Set(QuestionDifficulty.allCases)

    var isDefault: Bool { self == .default }

    /// 実際に対象とする難易度。購入・試用で使える範囲と掛け合わせる。
    ///
    /// - Parameter unspecified: 難易度を選んでいないときに何を対象とするか。
    ///   出題と集計で意味が変わりうるので、呼び出し側に決めさせる。
    func difficulties(
        availableDifficulties: Set<QuestionDifficulty>,
        unspecified: Set<QuestionDifficulty>
    ) -> Set<QuestionDifficulty> {
        let selected: Set<QuestionDifficulty> = difficulty.map { [$0] } ?? unspecified
        return selected.intersection(availableDifficulties)
    }

    /// 実際に対象とする分野。中分類を選んでいればそれが優先される
    var effectiveField: ExamField? {
        midCategory?.field ?? field
    }

    /// 画面に出す1行の説明。指定した条件だけを並べる
    var summary: String {
        var parts: [String] = []
        if let midCategory {
            parts.append(midCategory.displayName)
        } else if let field {
            parts.append(field.displayName)
        }
        if let difficulty { parts.append(difficulty.displayName) }
        return parts.isEmpty ? "すべて" : parts.joined(separator: " / ")
    }

    /// この問題が範囲に入るか
    func contains(
        _ question: QuestionMaster,
        availableDifficulties: Set<QuestionDifficulty>,
        unspecified: Set<QuestionDifficulty>
    ) -> Bool {
        guard difficulties(
            availableDifficulties: availableDifficulties,
            unspecified: unspecified
        ).contains(question.difficulty) else {
            return false
        }
        if let midCategory {
            return question.midCategory == midCategory
        }
        if let field, question.field != field { return false }
        return true
    }

    /// 分野を変えたら、その分野に属さない中分類の選択は捨てる。
    /// 残すと「ストラテジ系 / セキュリティ」のような0問確定の組み合わせが作れてしまう。
    mutating func setField(_ newField: ExamField?) {
        field = newField
        if let midCategory, midCategory.field != newField {
            self.midCategory = nil
        }
    }
}
