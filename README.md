# ITパスポート特訓（完全オフライン）

国家試験「ITパスポート試験」対策の4択問題アプリ。サーバー通信・アカウント登録なし。
`C:\System_Dev\eitango_app_01`（英検2級 英単語特訓）の骨格を流用し、
主データを「単語」から「4択問題」へ差し替えたもの。

| ドキュメント | 内容 |
| --- | --- |
| [docs/design-spec.md](docs/design-spec.md) | 設計仕様書。画面・データモデル・出題ロジック・課金・フェーズ計画 |
| [docs/question-authoring-prompt.md](docs/question-authoring-prompt.md) | AI作問プロンプト完全版と運用メモ |

## 現在の状態

**Phase 0（骨格移植）完了。** アプリは一通り動作する構成になっており、24問を同梱している。
Phase 1（問題を300問へ拡充）は §14 の手順に従って進める。

未着手の項目は「[残っている作業](#残っている作業)」を参照。

## ビルド方法（Mac実機なし・GitHub ActionsのmacOSランナーを使用）

`.xcodeproj` はコミットせず、[XcodeGen](https://github.com/yonaskolb/XcodeGen) が
`project.yml` から毎回生成する。

### CIでビルドとテストを確認する

GitHub にpushすると `.github/workflows/ios-build.yml` が動く。2段構成になっている。

1. **validate-seed**（Ubuntu）: `scripts/validate_seed.py` で問題データを検証する。
   macOSランナーは分単価が高い（privateリポジトリでは10倍消費）ため、
   シードの形式ミスでmacOSジョブを丸ごと無駄にしないよう手前で落とす
2. **build**（macOS）: ビルド + ユニットテスト + UIテスト。
   UIテストがシミュレータ上で画面を操作し、[`xcparse`](https://github.com/ChargePoint/xcparse) が
   `.xcresult` からPNGを抽出する。Actionsの実行結果ページ → Artifacts欄の
   **`ui-screenshots`** をダウンロードすると、実際に描画された画面を確認できる

### 問題データをローカルで検証する

```bash
python scripts/validate_seed.py
```

形式の検査に加えて、分野別・難易度別・中分類別の収録数を出す。
同じ検査は `ITPassportAppTests/SeedValidationTests.swift` からも走る
（CIでスクリプトを回すだけだと、手元でシードを編集したときに気付けないため）。

### TestFlightへ配信する

Actionsタブ → **TestFlight** ワークフロー → **Run workflow** を手動実行する。
必要なSecretsは以下の3つ。

| Secret | 内容 |
| --- | --- |
| `ASC_API_KEY_ID` | App Store Connect APIキーの Key ID |
| `ASC_API_ISSUER_ID` | 同 Issuer ID |
| `ASC_API_KEY_P8` | ダウンロードした `.p8` の中身（BEGIN/END行を含む全文） |

ビルド番号にはワークフローの実行番号を使う。App Store Connectは同じ（バージョン, ビルド番号）の
組を二度受け付けないため、必ず増える値が要る。

### Macが用意できた場合のローカル手順

```bash
brew install xcodegen
xcodegen generate
open ITPassportApp.xcodeproj
```

## ディレクトリ構成

```
ITPassportApp/
├── App/            # エントリポイント、ModelContainer初期化、Info.plist
├── Common/         # TabRouter・出題範囲・絞り込みなど、画面をまたぐ共有部品
├── Models/         # SwiftData @Model（QuestionMaster / UserProgress / StudyLog / 各種Enum）
├── Resources/
│   ├── question_master_seed.json   # 同梱問題データ（差し替えでアップデート）
│   └── Assets.xcassets/            # アプリアイコンとアプリ内ロゴ
├── Services/
│   ├── Audio/       # 効果音・BGMの波形合成（音声ファイルは同梱しない）
│   ├── DataSeeder/  # マスターデータのUpsert・学習履歴保持ロジック
│   ├── Purchase/    # 買い切り課金と試用期間
│   └── Study/       # 出題順・習熟度内訳・履歴集計（いずれも純粋関数）
├── Repositories/    # SwiftDataクエリの隠蔽層
└── Features/        # 画面ごとの View + ViewModel

ITPassportAppTests/     # ロジックのユニットテスト（間隔反復・出題順・課金・シード検証）
ITPassportAppUITests/   # 画面遷移してスクリーンショットを撮るXCUITest
scripts/validate_seed.py  # 問題データの機械検証
```

## データベース設計の要点

- `QuestionMaster`（マスター、Read-Only想定）と `UserProgress`（学習履歴、Read-Write）は
  `questionId` (String) でのみ緩く紐付け、SwiftDataの `@Relationship` は張らない
- アプリ更新時、同梱の `question_master_seed.json` の `version` が既適用バージョンより
  新しければ `QuestionMasterSeeder` がマスターをUpsertする。`UserProgress` には一切触れないため、
  問題データを総入れ替えしてもユーザーの進捗は保持される

### questionId は改名禁止

`ITP_<中分類コード>_<4桁連番>`（例: `ITP_SEC_0001`）。**公開後の改名は禁止**。
改名は「削除＋新規」になり、その問題の学習履歴が全ユーザーで失われる。
問題文・選択肢・解説の修正は自由（IDが同じなら履歴は保持される）。

誤りが見つかった問題は、削除ではなくシードから外す。Seederは孤児進捗を許容する設計になっている。

### 起動時の堅牢性

問題データが入らなくてもアプリが「起動しない」状態にはならないよう、以下の方針を取っている
（ベースアプリから引き継いだ設計。理由込みで維持すること）。

- 適用済みシードバージョンは UserDefaults、実データは SwiftData と保存先が分かれるため、
  両者は食い違いうる。`QuestionMaster` が0件ならバージョンに関わらず再シードする
- バージョンの記録は `context.save()` が成功した**後**に行う。逆順にすると save 失敗時に
  「バージョンだけ進んで問題が空」の状態が永続化され、以降のシードがスキップされて復旧できなくなる
- シード失敗は `AppContainer` でログに記録するだけで、起動は継続する
- 永続ストアを開けない場合はインメモリにフォールバックする

## 間隔反復（SRS）について

出題順は `Services/Study/StudyQueue.swift` が決める。ランダム出題ではなく、次の優先度で並べる。

1. 復習期限が来た問題（間違えた問題・間隔が満了した問題）
2. まだ一度も解いていない問題
3. 期限前の問題（期限が近い順）

間隔は Leitner ボックス方式で、`UserProgress.reviewIntervalDays` の固定テーブル（0/1/3/7/14/30日）を使う。
正解すると1段階上がって間隔が伸び、間違えると段階0に戻ってその日のうちに再出題される。

「習得済み」は7日間隔の復習に正解して初めて付く。1回解けただけの問題は本番では解けないことが多く、
間隔をあけて再度正解できて初めて定着とみなすため。

## 演習（クイズ）について

ベースの英単語アプリとの最大の差分。

- **1セット10問、制限時間なし。** 解説を読み込む学習体験と時間プレッシャーは両立しないため、
  ベースにあった1問10秒のタイマーは持たない
- **解答すると解説パネルが出て、そこで止まる。** 「次の問題へ」は解説の下に置く
  （解答ボタンと同じ位置に出すと、選択肢を押した勢いで解説を読まずに飛ばしてしまう）
- 解説は「正誤 → 自分が選んだ選択肢の解説 → 正解の解説 → 全選択肢の解説（折りたたみ）」の順。
  不正解のとき最も知りたいのは「なぜ自分の選択が違うのか」なので先頭に置く
- **選択肢の表示順は毎回シャッフルする。** 固定順だと「この問題の答えは3番目」という
  位置記憶で解けてしまい、間隔反復が測るものが知識ではなく並び順の記憶になる

## 分野別習熟度について

合格には総合600点だけでなく**分野ごとに300点**が要る（ストラテジ系・マネジメント系・テクノロジ系）。
総合点が足りていても1分野でも基準に届かなければ不合格になるため、
ホームでは全体の習熟度より分野別のバーを上に置き、いちばん遅れている分野への導線を出している。

分野別習熟度だけは習熟度の絞り込み設定（`masteryScope`）を適用しない。
合格基準の目安として見る数字なので、部分集合を出すと意味が変わるため。

## 課金と試用について

無料で配布し、買い切りのApp内課金で「応用問題（difficulty=3）」を出題対象に加える形にしている。
**広告とサブスクリプションは実装しない。**

初回起動から14日間は全問を試せる。**期間が終わっても演習は使えるまま**で、
変わるのは出題対象から応用問題が外れることだけ。問題一覧での閲覧・検索・解説の読み直しは常に全問できる。
機能を止める作りにしていないのは、一定期間後に動かなくなる体験版が App Review の拒否対象であり、
教育カテゴリでは「使えなくなった」という★1レビューを最も招くため。

### 判定の置き場所

| 型 | 役割 |
| --- | --- |
| `AccessRights` | 権利から出題できる難易度を決める値型。StoreKitにもUserDefaultsにも触れないのでそのままテストできる |
| `TrialManager` | 試用の起点をUserDefaultsに記録する。時計を戻して延長されないよう、観測済みの最新日時で判定する |
| `Entitlements` | StoreKitと試用をまとめ、画面に「いま何が出題できるか」を答える |

出題母集団（`QuestionRepository.fetchStudyPool`）は「ユーザーの設定（分野・難易度）」と
「権利」の**積**で決める。2つを1つのフラグに混ぜると、出題されない理由が設定なのか未購入なのかを
切り分けられず、画面の案内も出し分けられない。

`Transaction.updates` を購読して払い戻しを反映している。これを見ないと返金後も解放されたままになる。

## 問題データの作り方

1. `docs/question-authoring-prompt.md` のプロンプトに分野・中分類・難易度・問題数を埋めてAIに渡す
2. 出力を `docs/design-spec.md` §9.3 のチェックリストで**人手レビュー**する
   （国家試験対策アプリで誤答解説が間違っているのは致命的。レビューなしで取り込まない）
3. `questionId` を採番して `question_master_seed.json` に追記し、`version` を上げる
4. `python scripts/validate_seed.py` で機械検証する

中分類単位・20問前後のバッチで生成すると、偏りの検出とレビューがしやすい。

## 残っている作業

| 項目 | 内容 |
| --- | --- |
| アプリアイコン・ロゴ | `Resources/Assets.xcassets` は英単語アプリのものを仮置きしている。**差し替えが必要** |
| 公開URL | `AppConfig.privacyPolicyURL` / `supportURL` は仮のURL。公開前に実在のページへ差し替える |
| 問題数 | 現在24問。リリース最低ラインは300問（設計仕様書 §8.2） |
| 未収録の中分類 | 情報デザイン(DESIGN) / 情報メディア(MEDIA) / ハードウェア(HW) |
| シラバス確認 | 中分類はVer.6系の構成。最新シラバスと突き合わせること |
| 模擬試験モード | Phase 2（設計仕様書 §11） |

## 実装しないもの

- 広告
- サブスクリプション課金
- サーバー通信（購入・復元時のApple標準の通信を除く）
- タイピング機能（ベースアプリから意図的に削除）
