import Foundation

/// 出題分野（ITパスポート試験の3分野）。
///
/// 合格には総合600点だけでなく**分野ごとに300点**が要る。つまり利用者にとっての
/// 関心事は「全体で何問解けるか」ではなく「どの分野が落ちているか」なので、
/// 分野は絞り込みの一軸ではなく、習熟度表示の主軸として扱う。
enum ExamField: String, Codable, CaseIterable, Identifiable {
    case strategy
    case management
    case technology

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strategy: return "ストラテジ系"
        case .management: return "マネジメント系"
        case .technology: return "テクノロジ系"
        }
    }

    /// 本試験での出題数の目安（100問中）。出題プールの構成比と模擬試験の抽出に使う
    var questionsInExam: Int {
        switch self {
        case .strategy: return 35
        case .management: return 20
        case .technology: return 45
        }
    }

    var summary: String {
        switch self {
        case .strategy: return "企業活動・法務・経営戦略・システム戦略"
        case .management: return "開発技術・プロジェクト・サービス・監査"
        case .technology: return "基礎理論・コンピュータ・データベース・ネットワーク・セキュリティ"
        }
    }
}

/// シラバスの中分類。
///
/// rawValue は `questionId` にも埋め込むため（`ITP_SEC_0042`）、**公開後の改名は禁止**。
/// 改名は「削除+新規」になり、その問題の学習履歴が全ユーザーで失われる。
/// シラバス改訂で中分類が増えたときは、既存を変えずにケースを追加する。
enum MidCategory: String, Codable, CaseIterable, Identifiable {
    // ストラテジ系
    case corporate = "CORP"
    case legal = "LEGAL"
    case businessStrategy = "BSTRA"
    case techStrategy = "TSTRA"
    case businessIndustry = "BIZIND"
    case systemStrategy = "SYSSTRA"
    case systemPlanning = "SYSPLAN"
    // マネジメント系
    case systemDevelopment = "SYSDEV"
    case developmentManagement = "DEVMGT"
    case projectManagement = "PROJMGT"
    case serviceManagement = "SVCMGT"
    case audit = "AUDIT"
    // テクノロジ系
    case theory = "THEORY"
    case algorithm = "ALGO"
    case hardwareComponents = "HWCOMP"
    case systemComponents = "SYSCOMP"
    case software = "SW"
    case hardware = "HW"
    case design = "DESIGN"
    case media = "MEDIA"
    case database = "DB"
    case network = "NW"
    case security = "SEC"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .corporate: return "企業活動"
        case .legal: return "法務"
        case .businessStrategy: return "経営戦略マネジメント"
        case .techStrategy: return "技術戦略マネジメント"
        case .businessIndustry: return "ビジネスインダストリ"
        case .systemStrategy: return "システム戦略"
        case .systemPlanning: return "システム企画"
        case .systemDevelopment: return "システム開発技術"
        case .developmentManagement: return "ソフトウェア開発管理技術"
        case .projectManagement: return "プロジェクトマネジメント"
        case .serviceManagement: return "サービスマネジメント"
        case .audit: return "システム監査"
        case .theory: return "基礎理論"
        case .algorithm: return "アルゴリズムとプログラミング"
        case .hardwareComponents: return "コンピュータ構成要素"
        case .systemComponents: return "システム構成要素"
        case .software: return "ソフトウェア"
        case .hardware: return "ハードウェア"
        case .design: return "情報デザイン"
        case .media: return "情報メディア"
        case .database: return "データベース"
        case .network: return "ネットワーク"
        case .security: return "セキュリティ"
        }
    }

    /// 属する分野。中分類を選んだら分野は自動的に決まる（両方をユーザーに選ばせない）
    var field: ExamField {
        switch self {
        case .corporate, .legal, .businessStrategy, .techStrategy,
             .businessIndustry, .systemStrategy, .systemPlanning:
            return .strategy
        case .systemDevelopment, .developmentManagement, .projectManagement,
             .serviceManagement, .audit:
            return .management
        case .theory, .algorithm, .hardwareComponents, .systemComponents, .software,
             .hardware, .design, .media, .database, .network, .security:
            return .technology
        }
    }

    static func all(in field: ExamField) -> [MidCategory] {
        allCases.filter { $0.field == field }
    }
}

/// 問題の難易度。英単語版の語彙階層（VocabularyTier）に相当し、**課金の境界を兼ねる**。
///
/// 難易度で切っているのは、機能ではなく「出題される問題の範囲」を売り物にするため。
/// 機能を止める作りにすると、期間終了時に「使えなくなった」という受け取られ方をする。
enum QuestionDifficulty: Int, Codable, CaseIterable, Identifiable {
    /// 用語の定義レベル。シラバスの用語例をそのまま問う
    case basic = 1
    /// 本試験の中心レベル。用語の使い分け・場面判断
    case standard = 2
    /// 最新シラバス項目・計算問題・複数分野の複合知識
    case advanced = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .basic: return "基礎"
        case .standard: return "標準"
        case .advanced: return "応用"
        }
    }

    var summary: String {
        switch self {
        case .basic: return "用語の意味を問う入門レベル"
        case .standard: return "本試験の中心となるレベル"
        case .advanced: return "計算・複合知識・最新シラバス項目"
        }
    }
}

/// 選択肢のラベル。シードJSONのキーであり、表示順のシャッフル前の識別子でもある。
enum ChoiceLabel: String, Codable, CaseIterable, Identifiable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var id: String { rawValue }
}

/// 問題ごとの習熟段階。
///
/// 直近の正誤で反転させるのではなく、間隔反復の習得段階（`UserProgress.reviewBox`）から導く。
/// 1回正解しただけで「習得済み」にすると、実際には翌週忘れている問題まで習得扱いになり、
/// 習熟度の表示が学習の実態と乖離して意味を失う。
enum LearningStatus: String, Codable, CaseIterable, Identifiable {
    /// 一度も出題していない
    case notStudied
    /// 直近で間違えた、または復習期限が過ぎている
    case needsReview
    /// 正解を重ねている途中（復習間隔は1〜3日）
    case learning
    /// 1週間以上の間隔を空けても正解できた
    case memorized

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notStudied: return "未学習"
        case .needsReview: return "要復習"
        case .learning: return "学習中"
        case .memorized: return "習得済み"
        }
    }

    /// この段階に到達する条件。画面上の「iマーク」でそのまま見せる。
    var criteria: String {
        switch self {
        case .notStudied: return "まだ一度も出題されていない問題です。"
        case .needsReview: return "直近で間違えたか、復習の期限が来ている問題です。優先して出題されます。"
        case .learning: return "正解を重ねている途中の問題です。1〜3日の間隔で再出題されます。"
        case .memorized: return "1週間以上あけても正解できた問題です。以後は間隔を広げて確認します。"
        }
    }

    /// 問題一覧・習熟度バー・凡例で同じ見た目にするため、記号と色は段階自身に持たせる
    var symbolName: String {
        switch self {
        case .notStudied: return "circle"
        case .needsReview: return "exclamationmark.circle.fill"
        case .learning: return "arrow.triangle.2.circlepath.circle.fill"
        case .memorized: return "checkmark.circle.fill"
        }
    }
}
