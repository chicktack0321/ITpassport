import Foundation

/// アプリ全体で使う固定値と、外部に公開しているURLの置き場所。
///
/// 試験名・課金プロダクトID・公開URLがコードのあちこちに散っていると、
/// 変更のたびに取りこぼす。ここ1か所にまとめる。
enum AppConfig {

    // MARK: - 試験

    /// 画面に出す試験名
    static let examDisplayName = "ITパスポート試験"

    /// アプリ名（ホーム画面のアイコン下は Info.plist の CFBundleDisplayName が担う）
    static let appDisplayName = "ITパスポート特訓"

    /// 同梱する問題データ（拡張子を除いたファイル名）
    static let seedResourceName = "question_master_seed"

    /// App内課金のプロダクトID
    static let unlockProductID = "com.itpassport.app.unlock.advanced"

    // MARK: - 試験制度

    /// 本試験の出題数（うち採点対象92問）。模擬試験モードの基準に使う
    static let examTotalQuestions = 100
    static let examScoredQuestions = 92
    /// 本試験の制限時間（分）
    static let examDurationMinutes = 120

    /// 合格基準の説明。数字を画面に散らすと改定時に取りこぼすためここに置く
    static let passingCriteria = """
    総合評価点600点以上（1000点満点）かつ、\
    ストラテジ系・マネジメント系・テクノロジ系の各分野で300点以上（各1000点満点）。
    """

    // MARK: - 権利表記

    /// IPAの主催する国家試験。提携していると誤解させないため、アプリ内に常設する。
    static let trademarkNotice = """
    ITパスポート試験は独立行政法人 情報処理推進機構（IPA）が実施する国家試験です。\
    本アプリはIPAが承認・許諾したものではありません。\
    出題内容は公開されているシラバスに基づく独自作成の問題です。
    """

    // MARK: - 公開ページ

    /// App Store Connect にも同じURLを登録する（プライバシーポリシーは全アプリで必須）
    /// TODO: 公開前に実際のURLへ差し替える
    static let privacyPolicyURL = URL(string: "https://sites.google.com/view/itpassport-tokkun/privacy-policy")!
    static let supportURL = URL(string: "https://sites.google.com/view/itpassport-tokkun/support")!
}
