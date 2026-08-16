import Foundation

/// 初回起動から一定期間、全語彙を試せるようにする。
///
/// サーバーを持たない方針なので、起点は端末内（UserDefaults）に置く。
/// Keychain なら再インストールを跨いで残せるが、そこまでして試用を延ばす人は
/// もともと購入しない層であり、それより「購入者や正当な試用者を誤って締め出す」ほうが
/// 損害が大きいと判断して UserDefaults にしている。
@MainActor
final class TrialManager {
    /// 試用日数。
    ///
    /// 14日にしているのは、このアプリの習熟度の設計に合わせるため。
    /// 「覚えた」は7日間隔の復習に正解して初めて付き（最短4日目に到達）、
    /// その7日間隔の復習が実際に戻ってくるのは11日目になる。
    /// 7日で切ると「間隔をあけても思い出せた」という核心を体験する前に購入判断を迫ることになる。
    static let trialDays = 14

    private enum Key {
        static let startedAt = "trialStartedAt"
        static let lastSeenAt = "trialLastSeenAt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 起動時に呼ぶ。まだ始まっていなければ、この時点を試用の起点にする。
    func startIfNeeded(now: Date = .now) {
        if defaults.object(forKey: Key.startedAt) == nil {
            defaults.set(now, forKey: Key.startedAt)
        }
        recordSeen(now)
    }

    var startedAt: Date? { defaults.object(forKey: Key.startedAt) as? Date }

    var endsAt: Date? {
        startedAt.map { $0.addingTimeInterval(Double(Self.trialDays) * 86_400) }
    }

    func isActive(now: Date = .now) -> Bool {
        guard let endsAt else { return false }
        return effectiveNow(now) < endsAt
    }

    /// 残り日数（切り上げ）。試用が終わっていれば nil。
    func daysRemaining(now: Date = .now) -> Int? {
        guard let endsAt, isActive(now: now) else { return nil }
        let seconds = endsAt.timeIntervalSince(effectiveNow(now))
        return max(1, Int(ceil(seconds / 86_400)))
    }

    // MARK: - 時計の巻き戻し対策

    /// これまでに観測した最も新しい日時を控える。
    /// 端末の時計を戻して試用を延ばす操作を、サーバー無しで潰すための最低限の備え。
    private func recordSeen(_ now: Date) {
        let seen = defaults.object(forKey: Key.lastSeenAt) as? Date
        if seen == nil || now > seen! {
            defaults.set(now, forKey: Key.lastSeenAt)
        }
    }

    /// 判定に使う時刻。時計が巻き戻されていた場合は、観測済みの最も新しい日時で評価する。
    private func effectiveNow(_ now: Date) -> Date {
        guard let seen = defaults.object(forKey: Key.lastSeenAt) as? Date else { return now }
        return max(now, seen)
    }
}
