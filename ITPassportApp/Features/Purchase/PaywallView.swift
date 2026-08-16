import SwiftUI
import SwiftData

/// 応用問題を解放するための購入画面。
///
/// 売り物は「機能」ではなく「出題される問題の範囲」なので、何が増えるのかを問題数と内容で具体的に示す。
/// 機能を止める作りにはしていないため、ここで買わなくても学習は続けられることも明記する
/// （伏せると期間終了時に「使えなくなった」という受け取られ方をする）。
struct PaywallView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var entitlements = Entitlements.shared

    @State private var isWorking = false
    @State private var message: String?
    @State private var advancedCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    unlockCard
                    keepsWorkingNote
                    purchaseButtons
                    footnote
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("応用問題の解放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { countAdvancedQuestions() }
            .alert("お知らせ", isPresented: .constant(message != nil)) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            Text("合否を分ける応用問題まで、すべて出題対象に")
                .font(.title3).bold()
                .multilineTextAlignment(.center)
            if let remaining = entitlements.trialDaysRemaining {
                Text("お試し期間は残り\(remaining)日です")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var unlockCard: some View {
        DashboardCard(title: "解放される問題") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(advancedCount)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.blue)
                        .contentTransition(.numericText())
                    Text("問")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text("応用レベルの問題です。計算問題、複数分野にまたがる知識、生成AI・DX・ゼロトラストといった最新シラバス項目を含みます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Label("演習の出題対象に加わります", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Label("買い切りです。月額・年額の課金はありません", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                Label("機種変更しても同じ Apple アカウントなら無料で復元できます", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
            }
        }
    }

    /// 「買わないと使えなくなる」という誤解を先に潰す
    private var keepsWorkingNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("購入しなくても演習は引き続きお使いいただけます。出題される問題が基礎・標準までになります。問題一覧での閲覧・検索・解説の読み直しは全問そのままです。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var purchaseButtons: some View {
        VStack(spacing: 10) {
            Button {
                buy()
            } label: {
                HStack {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else if let price = entitlements.product?.displayPrice {
                        Text("\(price) で解放する")
                    } else {
                        Text("価格を読み込んでいます")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking || entitlements.product == nil)

            Button("購入を復元") { restore() }
                .disabled(isWorking)
        }
    }

    private var footnote: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Link("プライバシーポリシー", destination: AppConfig.privacyPolicyURL)
                Link("使い方・お問い合わせ", destination: AppConfig.supportURL)
            }
            .font(.caption)
            Text(AppConfig.trademarkNotice)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - 操作

    /// 解放される問題数は同梱データの改訂で変わるため、固定値ではなく実データから数える
    private func countAdvancedQuestions() {
        advancedCount = QuestionRepository(context: modelContext).count(difficulty: .advanced)
    }

    private func buy() {
        isWorking = true
        Task {
            let outcome = await entitlements.purchase()
            isWorking = false
            switch outcome {
            case .purchased:
                dismiss()
            case .cancelled:
                break
            case .pending:
                message = "購入の承認を待っています。承認されると自動的に解放されます。"
            case .failed(let reason):
                message = reason
            }
        }
    }

    private func restore() {
        isWorking = true
        Task {
            let restored = await entitlements.restorePurchases()
            isWorking = false
            if restored {
                dismiss()
            } else {
                message = "復元できる購入が見つかりませんでした。"
            }
        }
    }
}

#Preview {
    PaywallView()
        .modelContainer(for: [QuestionMaster.self, UserProgress.self, StudyLog.self], inMemory: true)
}
