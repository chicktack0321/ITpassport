import XCTest
@testable import ITPassportApp

/// 課金・試用の線引き。
///
/// 収益に直結するうえ、間違えても画面上は正常に見えてしまう。
/// StoreKit に依存しない値型として切り出してあるので、そのままテストできる。
final class AccessRightsTests: XCTestCase {

    func testLockedExcludesAdvanced() {
        let rights = AccessRights.locked

        XCTAssertFalse(rights.hasFullAccess)
        XCTAssertEqual(rights.availableDifficulties, [.basic, .standard])
        XCTAssertFalse(
            rights.availableDifficulties.contains(.advanced),
            "未購入かつ試用切れでは応用問題を出題しない"
        )
    }

    func testTrialGrantsFullAccess() {
        let rights = AccessRights(isPurchased: false, isTrialActive: true)

        XCTAssertTrue(rights.hasFullAccess)
        XCTAssertEqual(rights.availableDifficulties, Set(QuestionDifficulty.allCases))
    }

    func testPurchaseGrantsFullAccessEvenAfterTrialEnds() {
        let rights = AccessRights(isPurchased: true, isTrialActive: false)

        XCTAssertTrue(rights.hasFullAccess)
        XCTAssertEqual(rights.availableDifficulties, Set(QuestionDifficulty.allCases))
    }

    /// 権利が無くても基礎・標準は出題される。
    /// 機能そのものを止めると、一定期間後に動かなくなる体験版として審査で問題になり、
    /// 教育カテゴリでは「使えなくなった」という低評価を最も招く。
    func testLockedStillAllowsStudying() {
        let rights = AccessRights.locked
        XCTAssertFalse(rights.availableDifficulties.isEmpty)
    }

    func testSummaryDistinguishesPurchaseFromTrial() {
        XCTAssertEqual(AccessRights(isPurchased: true, isTrialActive: false).summary, "すべての問題（購入済み）")
        XCTAssertEqual(AccessRights(isPurchased: false, isTrialActive: true).summary, "すべての問題（お試し期間中）")
        XCTAssertEqual(AccessRights.locked.summary, "基礎・標準の問題")
    }
}

/// 試用期間の判定。時計の巻き戻しで延長されないことを含めて確認する。
@MainActor
final class TrialManagerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // 端末の実際の設定を汚さないよう、テストごとに専用のドメインを使う
        suiteName = "TrialManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testTrialStartsOnFirstLaunch() {
        let trial = TrialManager(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertNil(trial.startedAt)
        trial.startIfNeeded(now: start)

        XCTAssertEqual(trial.startedAt, start)
        XCTAssertTrue(trial.isActive(now: start))
    }

    func testStartIsRecordedOnlyOnce() {
        let trial = TrialManager(defaults: defaults)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let later = first.addingTimeInterval(3 * 86_400)

        trial.startIfNeeded(now: first)
        trial.startIfNeeded(now: later)

        XCTAssertEqual(trial.startedAt, first, "起点は初回のみ記録する")
    }

    func testTrialExpiresAfterConfiguredDays() {
        let trial = TrialManager(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        trial.startIfNeeded(now: start)

        let lastDay = start.addingTimeInterval(Double(TrialManager.trialDays) * 86_400 - 60)
        let afterEnd = start.addingTimeInterval(Double(TrialManager.trialDays) * 86_400 + 60)

        XCTAssertTrue(trial.isActive(now: lastDay))
        XCTAssertFalse(trial.isActive(now: afterEnd))
        XCTAssertNil(trial.daysRemaining(now: afterEnd), "終了後は残り日数を返さない")
    }

    func testDaysRemainingCountsUp() {
        let trial = TrialManager(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        trial.startIfNeeded(now: start)

        XCTAssertEqual(trial.daysRemaining(now: start), TrialManager.trialDays)
        XCTAssertEqual(trial.daysRemaining(now: start.addingTimeInterval(86_400)), TrialManager.trialDays - 1)
        // 残り1日を切っても0日とは出さない（「残り0日」は終了と区別がつかない）
        let almostOver = start.addingTimeInterval(Double(TrialManager.trialDays) * 86_400 - 3600)
        XCTAssertEqual(trial.daysRemaining(now: almostOver), 1)
    }

    /// 端末の時計を戻して試用を延ばす操作を、サーバー無しで潰せていること
    func testClockRollbackDoesNotExtendTrial() {
        let trial = TrialManager(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        trial.startIfNeeded(now: start)

        // 期間が終わるまで進める（観測済みの最新日時として記録される）
        let afterEnd = start.addingTimeInterval(Double(TrialManager.trialDays) * 86_400 + 86_400)
        trial.startIfNeeded(now: afterEnd)
        XCTAssertFalse(trial.isActive(now: afterEnd))

        // 時計を開始直後まで巻き戻しても、試用は復活しない
        let rolledBack = start.addingTimeInterval(3600)
        XCTAssertFalse(
            trial.isActive(now: rolledBack),
            "観測済みの最新日時で判定するため、時計を戻しても延長されない"
        )
    }
}
