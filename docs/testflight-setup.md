# TestFlight で実機確認できるようにする手順

Mac実機を持たない前提で、GitHub Actions から TestFlight へ配信するまでの手順。
英単語特訓・古文特訓と同じ体制なので、やることは既に2回経験済みのものと同じ。

CI（`ios-build.yml`）はシミュレータ上での動作までしか見ていない。
実機でしか分からないこと（触り心地、文字の詰まり、音、触覚フィードバック、
実際の購入フロー）はここから先で確認する。

## 進捗

| | 項目 | 状態 |
| --- | --- | --- |
| 0 | バンドルID の確定 | ✅ `com.itpassport.app` |
| 1 | 実機向けビルドの確認（dry run） | ✅ アーカイブ・埋め込み内容の検証とも通過 |
| 2 | GitHub Secrets | ⚠️ 3つ中2つ。`ASC_API_ISSUER_ID` が未登録 |
| 3 | App ID の登録 | ⬜ 未 |
| 4 | App Store Connect でのアプリ登録 | ⬜ 未 |
| 5 | 配信 | ⬜ 未 |

---

## 0. バンドルID（確定済み）

`com.itpassport.app`。`project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` に設定してある。

**App Store公開後は変更できない。** アプリの同一性そのものなので、変えると別アプリ扱いになり、
既存ユーザーは更新を受け取れず、購入も引き継げない。以降の手順ではこの値を使う。

参考までに、既存アプリは `com.eitango` をプレフィクスにしている
（英単語特訓 `com.eitango.app` / 古文特訓 `com.eitango.kobun`）。
本アプリは単独のプレフィクスを持つ形にした。

---

## 1. 先に実機向けビルドだけ確かめる（任意・準備不要）

App Store Connect の登録を始める前に、実機（arm64）向けのビルドが通るかだけを確認できる。
CIが見ているのはシミュレータ向けのビルドなので、ここで初めて分かることがある。

Actionsタブ → **TestFlight** → **Run workflow** → **検証のみ** にチェックを入れて実行。

Secretsもアプリ登録も不要。アーカイブを作り、埋め込まれた内容
（ビルド番号・暗号化宣言・表示名・アイコン・問題データ・プライバシーマニフェスト）を
検証するところまで走り、送信はしない。

これが緑なら、以降で失敗する余地は App Store Connect 側の登録だけに絞られる。

---

## 2. GitHub Secrets を登録する

英単語特訓・古文特訓と**同じApp Store Connect APIキーを使い回せる**。
キーは開発者アカウント単位なので、アプリごとに作り直す必要はない。

| Secret | 内容 | 状態 |
| --- | --- | --- |
| `ASC_API_KEY_ID` | APIキーの Key ID。`3V2TDP49RN` | ✅ 登録済み |
| `ASC_API_KEY_P8` | `.p8` の中身（BEGIN/END行を含む全文） | ✅ 登録済み |
| `ASC_API_ISSUER_ID` | Issuer ID（UUID形式） | ⚠️ **未登録** |

### 残り: Issuer ID

Key ID は `.p8` のファイル名に含まれているが、**Issuer ID はキーからは分からない**。
発行元アカウントの識別子なので、App Store Connect から取ってくる必要がある。

[App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) →
ユーザーとアクセス → 統合 → App Store Connect API。
キーの一覧の上に「Issuer ID」が UUID 形式で表示されているのでコピーする。

```bash
gh secret set ASC_API_ISSUER_ID -R chicktack0321/ITpassport --body "<Issuer ID>"
```

既存2アプリにも同じ値が入っているが、**GitHubのSecretsは書き込み専用で読み出せない**ため、
そちらから写すことはできない。

`.p8` を無くした場合も再ダウンロードできない。同じ画面で新しいキーを作り、
既存アプリのSecretsもそのとき合わせて更新する。

登録できたか確認:

```bash
gh secret list -R chicktack0321/ITpassport
```

---

## 3. App ID を登録する

[developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) →
Certificates, Identifiers & Profiles → Identifiers → **+**

- 種類: **App IDs** → **App**
- Description: `ITPassport Tokkun`（管理用の名前。何でもよい）
- Bundle ID: **Explicit** を選び、`com.itpassport.app` を入力（§0で変更したならそちら）
- Capabilities: 既定のままでよい（App内課金は明示的な有効化が不要）

先にここで登録しておく。CIの `-allowProvisioningUpdates` は証明書と
プロビジョニングプロファイルを自動で用意してくれるが、次の手順の
バンドルIDのドロップダウンには「登録済みのApp ID」しか出てこない。

---

## 4. App Store Connect にアプリを登録する

[App Store Connect](https://appstoreconnect.apple.com/apps) → マイApp → **+** → 新規App

| 項目 | 入れる値 |
| --- | --- |
| プラットフォーム | iOS |
| 名前 | App Storeに出る名前（30文字以内・全アプリで一意）。例: `ITパスポート特訓 - 過去問対策` |
| プライマリ言語 | 日本語 |
| バンドルID | §3で登録したものを選ぶ |
| SKU | 社内管理用の任意の文字列。例: `itpassport-tokkun` |
| ユーザーアクセス | フルアクセス |

**この登録をせずにワークフローを実行するとアップロードで失敗する。**
ビルド自体は通るので、失敗するのは最後の送信ステップになる。

---

## 5. 配信する

Actionsタブ → **TestFlight** ワークフロー → **Run workflow**

pushのたびに配信するとビルドが溜まりテスターへの通知も続くため、手動トリガーにしてある。

ワークフローは送信前に次を機械的に検証する。ここで止まったらアップロードはされない。

- ビルド番号が実行番号で更新されているか
- `ITSAppUsesNonExemptEncryption`（未宣言だと輸出コンプライアンスで配信が止まる）
- `CFBundleDisplayName`（無いとホーム画面が `ITPassportApp` になる）
- アプリアイコンと `Assets.car`（アイコンが無いビルドはApp Store Connectが弾く）
- `question_master_seed.json`（無いと起動はするが全画面が空になる）
- `PrivacyInfo.xcprivacy` と UserDefaults の利用理由の宣言

アップロード後、App Store Connect 側の処理に5〜15分かかる。
処理が終わると TestFlight タブにビルドが現れる。

### 内部テストで配信する（最短）

TestFlight → 内部テスト → グループを作り、自分のApple Accountを追加してビルドを割り当てる。
**内部テストは審査なしで即座に配信される**（App Store Connectのユーザー100人まで）。
動作確認だけならこれで足りる。

外部テスター（最大10,000人）へ配る場合は初回ビルドに Beta App Review が入り、
ベータ版アプリの説明・フィードバック用メールアドレス・連絡先の入力が必要になる。

---

## 6. 実機で確認したいこと

シミュレータでは分からない、または見落としやすい箇所。

| 見るところ | なぜ |
| --- | --- |
| 演習の解説パネル | 長い解説をスクロールしながら読めるか。解答後に解説の先頭へ送る動きが速すぎないか |
| 「次の問題へ」の位置 | 解説を読み終えた自然な位置にあるか。誤タップで飛ばしてしまわないか |
| 問題文と選択肢の折り返し | 実機の文字サイズ設定（特に大きめ）で詰まらないか |
| 触覚フィードバック | 正解1回・不正解3回の震え方。シミュレータでは再現されない |
| 効果音とBGM | 波形合成なので実機のスピーカーで耳障りでないか |
| ホームの分野別習熟度 | 3分野のバーが一目で比較できるか |
| 購入画面 | §7の通り、IAP未登録だと価格が出ない |

---

## 7. まだできないこと

**App内課金の購入フローはTestFlightでは試せない**（現時点）。
`com.itpassport.app.unlock.advanced` を App Store Connect に登録していないため、
購入画面は「価格を読み込んでいます」のまま止まり、購入ボタンは押せない。

購入まで確認したくなったら、App Store Connect →
（アプリ）→ 収益化 → App内課金 で非消耗型として登録する。

| 項目 | 値 |
| --- | --- |
| タイプ | 非消耗型 |
| 参照名 | 応用問題の解放 |
| 製品ID | `com.itpassport.app.unlock.advanced`（`AppConfig.unlockProductID` と一致させる） |
| 価格 | `Products.storekit` の表示は¥600だが、正はApp Store Connect側の設定 |

登録して「提出準備完了」になれば、TestFlightのビルドから
Sandbox環境で購入を試せる（実際の課金は発生しない）。

なお `Products.storekit` はシミュレータとUIテスト専用で、実機の挙動には影響しない。

---

## 8. うまくいかないときの切り分け

| 症状 | 原因と対処 |
| --- | --- |
| `ASC_API_KEY_P8 / ASC_API_KEY_ID が未設定です` | §2。Secretsが入っていない |
| 送信ステップで `No suitable application records were found` | §4のアプリ登録がまだ。バンドルIDの綴りも確認する |
| `No profiles for 'com.itpassport.app' were found` | §3のApp ID登録がまだ |
| ビルド番号が重複していると言われる | App Store Connectは同じ（バージョン, ビルド番号）を二度受け付けない。ワークフローは実行番号を使うので、通常は起きない。バージョンを上げるときは `project.yml` の `MARKETING_VERSION` を変更する |
| TestFlightにビルドが出てこない | 処理に5〜15分かかる。それ以上なら、App Store Connectから届くメールに理由が書かれている |
