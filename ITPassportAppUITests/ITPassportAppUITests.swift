import StoreKitTest
import XCTest

/// 実機やMacが手元になくても各画面の見た目を確認できるよう、主要画面を一通り遷移しながら
/// スクリーンショットを撮る。CIでは `xcparse` を使って `.xcresult` からPNGとして取り出し、
/// ワークフローのアーティファクトとしてアップロードする（ワークフロー側の設定を参照）。
final class ITPassportAppUITests: XCTestCase {

    override func setUpWithError() throws {
        // 1画面の遷移に失敗しても、それまでに撮れたスクリーンショットは失わずに済むよう続行する
        continueAfterFailure = true
    }

    func testCaptureAllScreens() throws {
        let app = XCUIApplication()
        app.launch()

        capture(app, "01_Home")

        // iマークの説明。最も長い「習熟度」の説明が見切れずに読めることを毎回撮って確かめる。
        let masteryInfo = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH '習熟度' AND label ENDSWITH 'の説明'"))
            .firstMatch
        if masteryInfo.waitForExistence(timeout: 5) {
            if !masteryInfo.isHittable {
                app.swipeUp()
                settle()
            }
            if masteryInfo.isHittable {
                masteryInfo.tap()
                settle()
                capture(app, "01a_MetricInfo")

                let closeButton = app.buttons["閉じる"]
                if closeButton.waitForExistence(timeout: 5) {
                    closeButton.tap()
                    settle()
                }
            }
        }

        // 分野別習熟度カードは画面下方にあり、初期表示では隠れていることがある。
        // 合格基準が分野別にあるため、このアプリで最も重要な表示のひとつ。
        app.swipeUp()
        settle()
        capture(app, "01b_Home_FieldMastery")

        // 演習: スタート → 出題 → 解答 → 解説
        let quizTab = app.tabBars.buttons["演習"]
        if quizTab.waitForExistence(timeout: 10) {
            quizTab.tap()
            settle()
            capture(app, "02_Quiz_Start")

            let startButton = app.buttons["quizStartButton"]
            if startButton.waitForExistence(timeout: 5), startButton.isHittable {
                startButton.tap()
                settle()
                capture(app, "03_Quiz_Question")

                // 解答すると解説パネルが出る。このアプリの中心機能なので必ず撮る。
                // 制限時間を持たないため、待っている間に状態が変わることはない。
                tapFirstChoice(app)
                settle()

                let nextButton = app.buttons["quizNextButton"]
                if nextButton.waitForExistence(timeout: 5) {
                    capture(app, "04_Quiz_Explanation")

                    // 「各選択肢の解説」を開いた状態も撮る。誤答選択肢の意味を示す部分が
                    // 折りたたまれているため、閉じたままだと見た目を確認できない。
                    let expandButton = app.buttons["各選択肢の解説を見る"]
                    if expandButton.exists, expandButton.isHittable {
                        expandButton.tap()
                        settle()
                        capture(app, "04b_Quiz_AllChoices")
                    }
                }
            }
        }

        // 問題一覧 → 問題詳細
        let listTab = app.tabBars.buttons["問題一覧"]
        if listTab.waitForExistence(timeout: 5) {
            listTab.tap()
            settle()
            capture(app, "05_QuestionList")

            // 問題文は出題データによって変わるため、文言ではなくセルの位置で掴む。
            // 一覧の先頭のセルであれば絞り込み行の増減に影響されない。
            let firstCell = app.cells.firstMatch
            if firstCell.waitForExistence(timeout: 5), firstCell.isHittable {
                firstCell.tap()
                settle()

                // 詳細に入れたときだけ撮って戻る
                if app.staticTexts["正解と解説"].waitForExistence(timeout: 5) {
                    capture(app, "06_QuestionDetail")

                    let backButton = app.navigationBars.buttons.element(boundBy: 0)
                    if backButton.exists {
                        backButton.tap()
                        settle()
                    }
                }
            }
        }

        let historyTab = app.tabBars.buttons["履歴"]
        if historyTab.waitForExistence(timeout: 5) {
            historyTab.tap()
            settle()
            capture(app, "07_StudyHistory")
        }
    }

    /// App内課金の審査用スクリーンショット。
    ///
    /// App Store Connect の「App内課金」→「審査に関する情報」に添える画像で、
    /// 利用者が実際に見る購入画面であること、価格・購入の復元・規約へのリンクが
    /// 確認できることが求められる。画面を変えるたびに撮り直すので自動化しておく。
    ///
    /// 価格はシミュレータでは App Store から取れないため、`Products.storekit` から
    /// テスト用のストアを立てて読み込ませる。スキーム側で指定する方法だと
    /// ストアフロントが米国のままで、ドル表記の画像になってしまう。
    func testCapturePurchaseScreen() throws {
        let store = try SKTestSession(configurationFileNamed: "Products")
        store.resetToDefaultState()
        store.clearTransactions()
        store.disableDialogs = true
        // 日本のApp Storeとして扱わせる。登録する価格と揃った画像にする
        store.storefront = "JPN"

        let app = XCUIApplication()
        app.launch()

        // ホームの「お試し期間」カードが購入画面への入口
        let accessCard = app.buttons["accessCard"]
        guard accessCard.waitForExistence(timeout: 10) else {
            XCTFail("ホームに購入画面への導線が見つかりません")
            return
        }
        accessCard.tap()
        settle()

        // 価格の読み込みを待つ。読めていないとボタンは「価格を読み込んでいます」のままで、
        // 審査用の画像として使えない。
        let purchaseButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '解放する'")
        ).firstMatch
        XCTAssertTrue(
            purchaseButton.waitForExistence(timeout: 15),
            "購入ボタンに価格が出ていません。StoreKitの設定ファイルが効いているか確認すること"
        )
        // 日本のApp Store向けなので円で出ていること。
        // ストアフロントの指定が抜けると米国扱いになり、ドル表記の画像ができてしまう。
        XCTAssertTrue(
            purchaseButton.label.contains("￥") || purchaseButton.label.contains("¥"),
            "価格が円になっていません: \(purchaseButton.label)"
        )
        // 「購入を復元」と規約リンクが同じ画面に写っていること
        XCTAssertTrue(app.buttons["購入を復元"].exists)
        XCTAssertTrue(app.links["プライバシーポリシー"].exists || app.buttons["プライバシーポリシー"].exists)

        settle()
        capture(app, "08_Purchase_ReviewScreenshot")
    }

    /// 4択の1つ目を押す。選択肢の文言は出題ごとに変わるため、識別子で掴む。
    /// 正解でも不正解でも解説が出るので、どれを押すかは問わない。
    @discardableResult
    private func tapFirstChoice(_ app: XCUIApplication) -> Bool {
        let choice = app.buttons.matching(identifier: "QuizChoice").firstMatch
        guard choice.waitForExistence(timeout: 5), choice.isHittable else { return false }
        choice.tap()
        return true
    }

    /// 画面遷移アニメーションが落ち着くのを待つ（厳密な待機条件がない箇所向けの簡易対応）
    private func settle() {
        Thread.sleep(forTimeInterval: 1)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
