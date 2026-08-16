import Foundation
import StoreKit
import Observation
import os

/// 買い切りアンロックと試用期間をまとめ、「いま何が出題できるか」を1か所で答える。
///
/// StoreKit 2 の `Transaction.currentEntitlements` は端末内で Apple の署名を検証するため、
/// 購入の確認にサーバーを持つ必要がない。通信は購入・復元の操作時に限られ、
/// 「完全オフラインで学習できる」という方針は崩れない。
@Observable
@MainActor
final class Entitlements {
    static let shared = Entitlements()

    private(set) var rights: AccessRights = .locked
    private(set) var trialDaysRemaining: Int?
    /// 価格の表示に使う。読み込めていないときは nil（購入ボタンは無効にする）
    private(set) var product: Product?

    private let logger = Logger(subsystem: "com.eitango.itpassport", category: "Entitlements")
    private let trial: TrialManager
    /// deinit（常にnonisolated）から安全にキャンセルできるよう、actor隔離チェックの対象から外す
    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    init(trial: TrialManager = TrialManager()) {
        self.trial = trial
    }

    // 画面から読む値
    var hasFullAccess: Bool { rights.hasFullAccess }
    var availableDifficulties: Set<QuestionDifficulty> { rights.availableDifficulties }
    var accessSummary: String { rights.summary }

    /// アプリ起動時に一度だけ呼ぶ
    func start() {
        refreshTrial()
        observeTransactionUpdates()
        Task {
            await refreshPurchaseState()
            await loadProduct()
        }
    }

    /// 試用の起点を確定し、残り日数を反映する。
    /// 画面に戻るたびに呼んでよい（起点は初回のみ記録される）。
    func refreshTrial(now: Date = .now) {
        trial.startIfNeeded(now: now)
        rights.isTrialActive = trial.isActive(now: now)
        trialDaysRemaining = trial.daysRemaining(now: now)
    }

    // MARK: - StoreKit

    private func loadProduct() async {
        do {
            product = try await Product.products(for: [AppConfig.unlockProductID]).first
        } catch {
            // 電波が無い場所では読めなくて当然なので、失敗しても学習機能には影響させない
            logger.notice("商品情報を取得できませんでした: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 端末が持っている購入権を読み直す
    func refreshPurchaseState() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // revocationDate が入るのは払い戻し・ファミリー共有の解除など。
            // ここを見ないと返金後も解放されたままになる。
            guard transaction.productID == AppConfig.unlockProductID,
                  transaction.revocationDate == nil else { continue }
            purchased = true
        }
        rights.isPurchased = purchased
    }

    /// 別端末での購入や払い戻しを反映するために購読しておく
    private func observeTransactionUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshPurchaseState()
            }
        }
    }

    enum PurchaseOutcome {
        case purchased
        case cancelled
        /// 承認待ち（ファミリー共有の購入承認など）。完了は `Transaction.updates` 側で拾う
        case pending
        case failed(String)
    }

    func purchase() async -> PurchaseOutcome {
        guard let product else { return .failed("商品情報を取得できませんでした。通信環境をご確認ください。") }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("購入を確認できませんでした。")
                }
                await transaction.finish()
                await refreshPurchaseState()
                return .purchased
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("購入を完了できませんでした。")
            }
        } catch {
            logger.error("購入に失敗しました: \(error.localizedDescription, privacy: .public)")
            return .failed("購入を完了できませんでした。")
        }
    }

    /// 機種変更・再インストール後の復元。App Review で導線の有無を確認される。
    func restorePurchases() async -> Bool {
        try? await AppStore.sync()
        await refreshPurchaseState()
        return rights.isPurchased
    }

    deinit {
        updatesTask?.cancel()
    }
}
