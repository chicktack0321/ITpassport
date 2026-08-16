import XCTest
import SwiftData
@testable import ITPassportApp

/// 出題範囲の絞り込みと、課金の権利との掛け合わせ。
///
/// 「設定で絞った」と「未購入で出題されない」を混ぜると、利用者が原因を判断できず、
/// 画面の案内も出し分けられない。積として扱えていることを確認する。
@MainActor
final class StudyScopeTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([QuestionMaster.self, UserProgress.self, StudyLog.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    @discardableResult
    private func insert(
        _ id: String,
        midCategory: MidCategory,
        difficulty: QuestionDifficulty
    ) -> QuestionMaster {
        let question = QuestionMaster(
            questionId: id,
            questionText: "問題文 \(id)",
            choiceA: "A", choiceB: "B", choiceC: "C", choiceD: "D",
            correctChoice: .a,
            explanation: "解説",
            explanationA: "正解。", explanationB: "不正解。",
            explanationC: "不正解。", explanationD: "不正解。",
            field: midCategory.field,
            midCategory: midCategory,
            syllabusVersion: "6.3",
            difficulty: difficulty
        )
        context.insert(question)
        return question
    }

    // MARK: - StudyScope の判定

    func testDefaultScopeIncludesEveryDifficultyWhenUnlocked() {
        let scope = StudyScope.default
        let question = insert("ITP_SEC_0001", midCategory: .security, difficulty: .advanced)

        XCTAssertTrue(
            scope.contains(
                question,
                availableDifficulties: Set(QuestionDifficulty.allCases),
                unspecified: StudyScope.studyDefaultDifficulties
            ),
            "英単語版と違い、既定の出題範囲から基礎を外さない。用語の定義を問う問題も本試験に出るため"
        )
    }

    /// 権利が無いと応用問題は出題対象から外れる
    func testLockedRightsExcludeAdvancedQuestions() {
        let scope = StudyScope.default
        let advanced = insert("ITP_SEC_0001", midCategory: .security, difficulty: .advanced)
        let standard = insert("ITP_SEC_0002", midCategory: .security, difficulty: .standard)

        let available = AccessRights.locked.availableDifficulties

        XCTAssertFalse(
            scope.contains(advanced, availableDifficulties: available, unspecified: StudyScope.studyDefaultDifficulties)
        )
        XCTAssertTrue(
            scope.contains(standard, availableDifficulties: available, unspecified: StudyScope.studyDefaultDifficulties)
        )
    }

    func testFieldFilter() {
        var scope = StudyScope.default
        scope.setField(.strategy)

        let strategy = insert("ITP_CORP_0001", midCategory: .corporate, difficulty: .basic)
        let technology = insert("ITP_SEC_0001", midCategory: .security, difficulty: .basic)
        let all = Set(QuestionDifficulty.allCases)

        XCTAssertTrue(scope.contains(strategy, availableDifficulties: all, unspecified: all))
        XCTAssertFalse(scope.contains(technology, availableDifficulties: all, unspecified: all))
    }

    /// 中分類を選んだら、分野の指定より中分類が優先される
    func testMidCategoryOverridesField() {
        var scope = StudyScope.default
        scope.midCategory = .security

        let security = insert("ITP_SEC_0001", midCategory: .security, difficulty: .basic)
        let network = insert("ITP_NW_0001", midCategory: .network, difficulty: .basic)
        let all = Set(QuestionDifficulty.allCases)

        XCTAssertTrue(scope.contains(security, availableDifficulties: all, unspecified: all))
        XCTAssertFalse(scope.contains(network, availableDifficulties: all, unspecified: all))
        XCTAssertEqual(scope.effectiveField, .technology, "中分類から分野が決まる")
    }

    /// 分野を変えたら、その分野に属さない中分類の選択は捨てる。
    /// 残すと「ストラテジ系 / セキュリティ」のような0問確定の組み合わせが作れてしまう。
    func testChangingFieldClearsIncompatibleMidCategory() {
        var scope = StudyScope.default
        scope.setField(.technology)
        scope.midCategory = .security

        scope.setField(.strategy)

        XCTAssertNil(scope.midCategory)
        XCTAssertEqual(scope.field, .strategy)
    }

    func testChangingFieldKeepsCompatibleMidCategory() {
        var scope = StudyScope.default
        scope.setField(.technology)
        scope.midCategory = .security

        scope.setField(.technology)

        XCTAssertEqual(scope.midCategory, .security, "同じ分野に属する中分類は残す")
    }

    func testSummaryDescribesOnlySpecifiedConditions() {
        XCTAssertEqual(StudyScope.default.summary, "すべて")

        var scope = StudyScope.default
        scope.setField(.management)
        XCTAssertEqual(scope.summary, "マネジメント系")

        scope.difficulty = .advanced
        XCTAssertEqual(scope.summary, "マネジメント系 / 応用")

        scope.midCategory = .audit
        XCTAssertEqual(scope.summary, "システム監査 / 応用", "中分類を選んだら分野ではなく中分類を出す")
    }

    // MARK: - リポジトリ経由の出題プール

    /// 出題プールは「ユーザー設定 × 権利」の積になる
    func testStudyPoolIsIntersectionOfScopeAndRights() {
        insert("ITP_CORP_0001", midCategory: .corporate, difficulty: .basic)
        insert("ITP_CORP_0002", midCategory: .corporate, difficulty: .advanced)
        insert("ITP_SEC_0001", midCategory: .security, difficulty: .basic)
        insert("ITP_SEC_0002", midCategory: .security, difficulty: .advanced)

        let repository = QuestionRepository(context: context)

        var scope = StudyScope.default
        scope.setField(.strategy)

        // 設定でストラテジ系に絞り、権利が無い（応用が外れる）→ 基礎の1問だけ
        let locked = repository.fetchStudyPool(
            scope: scope,
            availableDifficulties: AccessRights.locked.availableDifficulties
        )
        XCTAssertEqual(locked.map(\.questionId), ["ITP_CORP_0001"])

        // 同じ設定で権利がある → ストラテジ系の2問
        let unlocked = repository.fetchStudyPool(
            scope: scope,
            availableDifficulties: Set(QuestionDifficulty.allCases)
        )
        XCTAssertEqual(unlocked.count, 2)
    }

    /// 習熟度の集計は権利で絞らない。
    /// 未購入でも応用問題の習熟度を見られるほうが、何を解放することになるのかが伝わる。
    func testMasteryScopeIgnoresPurchaseState() {
        insert("ITP_SEC_0001", midCategory: .security, difficulty: .basic)
        insert("ITP_SEC_0002", midCategory: .security, difficulty: .advanced)

        let repository = QuestionRepository(context: context)
        let questions = repository.fetchQuestions(matching: .default)

        XCTAssertEqual(questions.count, 2, "集計では応用問題も数える")
    }

    func testCountsByField() {
        insert("ITP_CORP_0001", midCategory: .corporate, difficulty: .basic)
        insert("ITP_PROJMGT_0001", midCategory: .projectManagement, difficulty: .basic)
        insert("ITP_SEC_0001", midCategory: .security, difficulty: .basic)
        insert("ITP_NW_0001", midCategory: .network, difficulty: .basic)

        let counts = QuestionRepository(context: context).countsByField()

        XCTAssertEqual(counts[.strategy], 1)
        XCTAssertEqual(counts[.management], 1)
        XCTAssertEqual(counts[.technology], 2)
    }

    func testCountByDifficulty() {
        insert("ITP_SEC_0001", midCategory: .security, difficulty: .advanced)
        insert("ITP_SEC_0002", midCategory: .security, difficulty: .advanced)
        insert("ITP_SEC_0003", midCategory: .security, difficulty: .basic)

        let repository = QuestionRepository(context: context)

        XCTAssertEqual(repository.count(difficulty: .advanced), 2)
        XCTAssertEqual(repository.count(difficulty: .basic), 1)
        XCTAssertEqual(repository.count(difficulty: .standard), 0)
    }
}
