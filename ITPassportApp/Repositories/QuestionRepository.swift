import Foundation
import SwiftData

/// QuestionMaster への問い合わせを集約する。
/// ViewModelがSwiftDataのクエリ構文に直接依存しないようにする層。
@MainActor
struct QuestionRepository {
    let context: ModelContext

    func fetchAll() -> [QuestionMaster] {
        (try? context.fetch(FetchDescriptor<QuestionMaster>(sortBy: [SortDescriptor(\.questionId)]))) ?? []
    }

    func fetchCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<QuestionMaster>())) ?? 0
    }

    /// 演習の出題母集団。
    ///
    /// 「ユーザーが選んだ範囲」（`StudyScope`）と「購入・試用で使える範囲」（`AccessRights`）の
    /// 積を取る。2つを混ぜて1つの条件にすると、出題されない理由が設定なのか未購入なのかを
    /// 切り分けられなくなり、画面の案内も出し分けられない。
    func fetchStudyPool(
        scope: StudyScope = StudySettings.studyScope,
        availableDifficulties: Set<QuestionDifficulty> = Entitlements.shared.availableDifficulties
    ) -> [QuestionMaster] {
        fetchAll().filter {
            scope.contains(
                $0,
                availableDifficulties: availableDifficulties,
                unspecified: StudyScope.studyDefaultDifficulties
            )
        }
    }

    /// 習熟度の集計など、出題ではない用途で範囲を適用する。
    ///
    /// 購入状況では絞らない（未購入でも「応用問題の習熟度」を見られるほうが、
    /// 何を解放することになるのかが伝わる）。
    func fetchQuestions(matching scope: StudyScope) -> [QuestionMaster] {
        fetchAll().filter {
            scope.contains(
                $0,
                availableDifficulties: StudyScope.allDifficulties,
                unspecified: StudyScope.allDifficulties
            )
        }
    }

    /// 指定した範囲に入る問題数。出題を始める前に「この条件で何問あるか」を見せるために使う
    func countStudyPool(
        scope: StudyScope,
        availableDifficulties: Set<QuestionDifficulty> = Entitlements.shared.availableDifficulties
    ) -> Int {
        fetchStudyPool(scope: scope, availableDifficulties: availableDifficulties).count
    }

    /// 難易度ごとの問題数。購入画面で「何問解放されるか」を実データから出すのに使う
    func count(difficulty: QuestionDifficulty) -> Int {
        let raw = difficulty.rawValue
        let descriptor = FetchDescriptor<QuestionMaster>(predicate: #Predicate { $0.difficultyRaw == raw })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// 分野ごとの問題数。ホームの分野別習熟度で分母に使う
    func countsByField() -> [ExamField: Int] {
        fetchAll().reduce(into: [:]) { counts, question in
            counts[question.field, default: 0] += 1
        }
    }
}
