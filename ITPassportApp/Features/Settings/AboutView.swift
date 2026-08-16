import SwiftUI

/// このアプリについて。
///
/// 国家試験の名称を使うため、IPAと提携していないことの明示がApp Reviewで問われうる。
/// あわせて、購入の復元・プライバシーポリシー・問い合わせ先という
/// 「審査で所在を確認される導線」をここ1か所にまとめている。
struct AboutView: View {
    @State private var entitlements = Entitlements.shared
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppConfig.appDisplayName).font(.headline)
                            Text(AppConfig.examDisplayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("通信を一切行いません。学習の記録は端末内にのみ保存されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("利用状況") {
                LabeledContent("出題できる問題", value: entitlements.accessSummary)
                if let remaining = entitlements.trialDaysRemaining {
                    LabeledContent("お試し期間", value: "残り\(remaining)日")
                }
            }

            Section("試験の概要") {
                LabeledContent("出題数", value: "\(AppConfig.examTotalQuestions)問（採点対象\(AppConfig.examScoredQuestions)問）")
                LabeledContent("試験時間", value: "\(AppConfig.examDurationMinutes)分")
                VStack(alignment: .leading, spacing: 4) {
                    Text("合格基準").font(.subheadline)
                    Text(AppConfig.passingCriteria)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section {
                Button {
                    restore()
                } label: {
                    HStack {
                        Text("購入を復元")
                        if isRestoring {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRestoring)
            } footer: {
                // 機種変更・再インストール時の案内はストアの審査でも所在を見られる
                Text("機種変更やアプリの入れ直しのあと、同じ Apple アカウントであれば無料で復元できます。")
            }

            Section("リンク") {
                Link("プライバシーポリシー", destination: AppConfig.privacyPolicyURL)
                Link("使い方・お問い合わせ", destination: AppConfig.supportURL)
            }

            Section {
                Text(AppConfig.trademarkNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("このアプリについて")
        .navigationBarTitleDisplayMode(.inline)
        .alert("購入の復元", isPresented: .constant(restoreMessage != nil)) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            let restored = await entitlements.restorePurchases()
            isRestoring = false
            restoreMessage = restored
                ? "購入を復元しました。すべての問題が出題対象になります。"
                : "復元できる購入が見つかりませんでした。"
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
