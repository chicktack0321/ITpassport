import Foundation

/// 出題できる問題の範囲を決める権利。
///
/// StoreKit にも UserDefaults にも触れない値型にしてある。
/// 「試用中は全問、期間後は基礎と標準まで」という線引きは収益に直結し、
/// 間違えても画面上は正常に見えてしまうため、ここだけを取り出してテストできるようにする。
struct AccessRights: Equatable {
    /// 買い切りのアンロックを購入済みか
    var isPurchased: Bool
    /// 初回起動から14日間の試用期間中か
    var isTrialActive: Bool

    static let locked = AccessRights(isPurchased: false, isTrialActive: false)

    var hasFullAccess: Bool { isPurchased || isTrialActive }

    /// 出題の対象にできる難易度。
    ///
    /// 権利が無くても機能そのものは止めない。止まるのは応用問題が出題対象から
    /// 外れることだけで、問題一覧での閲覧・検索・解説の読み直しは常に全問できる。
    var availableDifficulties: Set<QuestionDifficulty> {
        hasFullAccess ? Set(QuestionDifficulty.allCases) : [.basic, .standard]
    }

    /// 画面に出す現在の状態
    var summary: String {
        if isPurchased { return "すべての問題（購入済み）" }
        if isTrialActive { return "すべての問題（お試し期間中）" }
        return "基礎・標準の問題"
    }
}
