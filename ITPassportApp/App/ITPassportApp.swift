import SwiftUI
import SwiftData

@main
struct ITPassportApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                // 試用の起点の記録・購入状態の読み直し・払い戻しの購読をここで始める。
                // 起動直後に確定させないと、権利が無い状態で一瞬だけ全問が出題対象になる。
                .task { Entitlements.shared.start() }
        }
        .modelContainer(AppContainer.shared)
    }
}

/// ソーシャル機能を一切持たないため、タブは「学習」に直結する最小構成にする
struct RootTabView: View {
    @State private var router = TabRouter()

    var body: some View {
        TabView(selection: Bindable(router).selectedTab) {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house") }
                .tag(AppTab.home)

            QuizView()
                .tabItem { Label("演習", systemImage: "checkmark.circle") }
                .tag(AppTab.quiz)

            QuestionListView()
                .tabItem { Label("問題一覧", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.questionList)

            StudyHistoryView()
                .tabItem { Label("履歴", systemImage: "chart.bar") }
                .tag(AppTab.history)
        }
        .environment(router)
    }
}
