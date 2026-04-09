# TitechAppProject 技術分析メモ

作成日: 2026-04-09  
対象: [TitechAppProject](https://github.com/TitechAppProject)  
補助ソース: [公式サイト](https://titech.app)

## 1. 結論

`TitechAppProject` の公開 GitHub から見える技術的な本体は、単一のアプリではなく「大学の複数サービスを統合利用するための接続基盤」です。実装の中心は次の 3 系統です。

1. ポータル認証の自動化
2. 教務・LMS 情報の取得/更新
3. iOS / Android 向けに同等機能を提供するクロス実装

公開リポジトリ構成から、`Titech App` 本体は非公開または別管理で、公開されているのはそれを支える SDK 群である可能性が高いです。

## 2. リポジトリ群の技術分類

### ポータル認証

- [titech-portal-kit](https://github.com/TitechAppProject/titech-portal-kit)
- [titech-portal-core-kotlin](https://github.com/TitechAppProject/titech-portal-core-kotlin)
- [science-tokyo-portal-kit](https://github.com/TitechAppProject/science-tokyo-portal-kit)
- [science-tokyo-portal-kotlin](https://github.com/TitechAppProject/science-tokyo-portal-kotlin)

役割:
- 大学ポータルへのログインフローをコード化
- フォーム解析、hidden input の再送、Cookie セッション維持
- 旧東京工業大学ポータルと、後継の `Science Tokyo` 環境の両方を吸収

実装上の特徴:
- Swift 系は `Kanna` で HTML をパース
- Kotlin 系は `jsoup` を使用
- `Science Tokyo` 側では TOTP 生成までライブラリ内で実装
- ログイン成功判定はタイトル/本文の文字列マッチで行う

### 教務情報

- [titech-kyomu-kit](https://github.com/TitechAppProject/titech-kyomu-kit)
- [titech-kyomu-core-kotlin](https://github.com/TitechAppProject/titech-kyomu-core-kotlin)

役割:
- 教務 Web のトップページ・レポート確認画面を解析
- 科目名、曜日時限、担当教員、履修コード、提出状態などを構造化

実装上の特徴:
- HTML の表をスクレイピングして `KyomuCourse` 相当のモデルに変換
- 日本語/英語 UI、旧学名/新学名、一時保存状態までテストケース化

### LMS / Moodle

- [t2schola-core-swift](https://github.com/TitechAppProject/t2schola-core-swift)
- [t2schola-core-kotlin](https://github.com/TitechAppProject/t2schola-core-kotlin)
- [moodle-core-swift](https://github.com/TitechAppProject/moodle-core-swift)
- [moodle-core-kotlin](https://github.com/TitechAppProject/moodle-core-kotlin)
- [titech-moodle](https://github.com/TitechAppProject/titech-moodle)

役割:
- Moodle/T2SCHOLA の Web Service API クライアント
- 課題、コース内容、通知、フォーラム、クイズ、ワークショップを取得
- 一部はコメント追加/削除や既読更新など更新系 API も持つ

実装上の特徴:
- `T2Schola` は最初にダッシュボード遷移を確立してから token を取得
- `ScienceTokyoPortal` は LMS ページ遷移から `moodlemobile://token=` を抽出して wsToken を得る
- `moodle-core-*` は取得した token を使う純 API クライアントとして分離されている

### Wi-Fi 認証

- [tokyotech-wifi-kit](https://github.com/TitechAppProject/tokyotech-wifi-kit)

役割:
- 学内 Wi-Fi captive portal のログイン補助
- HTML ログインページを解析して POST 先 URL とフォーム値を復元

### その他

- [ocwi-news-viewer](https://github.com/TitechAppProject/ocwi-news-viewer)
- [titech-ocw-scraping](https://github.com/TitechAppProject/titech-ocw-scraping)
- [circle-welcome](https://github.com/TitechAppProject/circle-welcome)
- [titechappproject-corp-web](https://github.com/TitechAppProject/titechappproject-corp-web)

これらは周辺ツールや広報サイトで、公開コードの技術的主軸ではありません。

## 3. 技術スタック

### Swift 系

共通傾向:
- Swift Package Manager ベース
- 非同期 API は `async/await`
- HTML 解析に `Kanna`
- テストに HTML fixture を多用

確認できた依存:
- `titech-portal-kit`: `Kanna`
- `titech-kyomu-kit`: `Kanna`
- `science-tokyo-portal-kit`: `Kanna`, `swift-crypto`
- `t2schola-core-swift`: `Kanna`
- `tokyotech-wifi-kit`: `Kanna`
- `moodle-core-swift`: 外部依存なし

読み取れる設計:
- 「ページ遷移を辿るクライアント」と「個別リクエスト型」を分離
- `Request` オブジェクトでエンドポイントと送信内容をカプセル化
- HTML を fixture 化してユニットテストしているので、UI 変更への回帰検知を意識している

### Kotlin 系

共通傾向:
- JVM ライブラリ
- Gradle Kotlin DSL
- `maven-publish` と `signing` を使い Maven Central 配布を想定
- 非同期処理は `kotlinx-coroutines`
- HTML 解析は `jsoup`
- JSON 系は `kotlinx-serialization`

確認できた公開設定:
- `groupId = "app.titech"`
- 例: `artifactId = "titech-portal-core"`, `artifactId = "science-tokyo-portal"`, `artifactId = "moodle-core"`

読み取れる設計:
- Android アプリ内 private module ではなく、外部公開可能な汎用ライブラリとして整備
- 署名や `sourcesJar`/`javadocJar` まであり、配布前提の品質管理が入っている

## 4. 代表フローの技術解剖

### 4.1 旧ポータルログイン

`titech-portal-kit` の `TitechPortal.login(account:)` から見える流れ:

1. パスワードページ取得
2. HTML 内の `input` を抽出
3. ユーザー名・パスワードを注入して submit
4. OTP 選択ページなら `GridAuthOption` を選択
5. マトリクス認証ページに進む
6. ページに表示された現在要求マトリクスを正規表現で抽出
7. ユーザー保持の matrix code 辞書から該当セル値を埋める
8. 送信後、タイトルが `リソース メニュー` なら成功

要点:
- DOM 操作というより「HTML 断片をパースして hidden/input/select を再構成する」スクレイピング型
- 認証フローの状態遷移をコード側で持っている
- UI 文字列依存が強いため、ポータル文言変更に弱い

### 4.2 Science Tokyo ポータルログイン

`science-tokyo-portal-kit` の `ScienceTokyoPortal.login(account:)` から見える流れ:

1. username ページ取得
2. CSRF token を `meta` から回収
3. identifier submit
4. password submit
5. 認証方式選択ページ取得
6. `totpSecret` から TOTP を計算
7. OTP submit
8. JavaScript の `window.location = "..."` から待機 URL を抽出
9. 待機ページを経由してリソース一覧へ

要点:
- 旧ポータルの matrix 認証から、より現代的な username/password/TOTP フローへ移行
- `swift-crypto` と `Base32`, `TOTPCalculator` が入っており、OTP アプリ互換のコード生成まで担う
- 認証後そのまま LMS token 取得機能までつながっている

### 4.3 教務スクレイピング

`titech-kyomu-kit` の `parseReportCheckPage` から見える流れ:

1. レポート確認ページの表行を走査
2. 各列から学期、曜日時限、教室、科目コード、教員、提出可否を抽出
3. 時限情報は正規表現で `Mon1-2` / `火3-4` の両方に対応
4. `KyomuCourse` の配列へ正規化

要点:
- データソースが公式 API ではなく HTML 画面そのもの
- 文言差分やレイアウト差分に対して、fixture を増やして耐性を持たせている

### 4.4 LMS token 取得と Moodle API

公開コードから読み取れる分離は次の通りです。

1. ポータル系ライブラリで認証済みセッションを作る
2. LMS 画面遷移で token を取得する
3. `moodle-core-*` / `t2schola-core-*` で Web Service API を叩く

これにより、認証の不安定な部分と Moodle API の安定した部分を分離しています。設計としてかなり妥当です。

## 5. アーキテクチャ上の特徴

### 共通パターン

- HTTP 層を `HTTPClient` / `APIClient` として抽象化
- 画面ごと・API ごとに `Request` 型を切り出し
- 成功判定は HTML 文言か Cookie 名で検証
- 旧環境と新環境を並行運用
- Swift/Kotlin で同じ機能を重複実装

### 強み

- 学内システムの複雑な認証導線を SDK 化できている
- iOS / Android で挙動を揃えやすい
- fixture ベースのテストで破壊的変更を早めに検出できる
- Kotlin 版は Maven Central 配布を意識しており再利用性が高い

### 弱み

- HTML 文言や DOM 変更に脆い
- 学内サービスの非公開仕様に依存しやすい
- Swift/Kotlin 両実装で仕様同期コストが高い
- 認証成功判定の一部が文字列検索ベースで、頑健性に限界がある

## 6. 技術的に見た全体像

この組織は「学生向けスーパーアプリのバックエンド代替レイヤ」をクライアントサイドで実装している、と見るのが近いです。大学側が一貫した公式 API を出していない部分を、以下で埋めています。

- スクレイピング
- セッション継続
- 認証自動化
- LMS token 仲介
- 取得データのドメインモデル化

プロダクトとしては `Titech App` が前面に出ていますが、技術の核は「複数の学内Webを 1 つのモバイルUXへ変換する接続層」です。

## 7. 時系列の読み取り

公開履歴から見える流れ:

- 2020: `ocwi-news-viewer`, `t2schola-core-swift`
- 2021: `titech-portal-kit`
- 2022: `tokyotech-wifi-kit`, `titech-moodle`, `titech-kyomu-kit`, `OCW` 系
- 2023: Kotlin 版コアライブラリ拡充
- 2024: 組織サイト更新
- 2025: `science-tokyo-*`, `moodle-core-*` が追加

推測:
- 東京工業大学から Science Tokyo への移行に合わせ、ポータル認証と LMS 接続を作り直している
- `t2schola` 依存を一般化し、`moodle-core` として共通化している

これはリポジトリ名・作成時期・ファイル構成からの推測です。

## 8. 再現手順

このディレクトリには、同じ情報を GitHub から再取得するためのスクリプトを追加しています。

ファイル:
- [collect_titechappproject_data.sh](/Users/sikurehayu/Desktop/app/kcm_app/ぶんせき/collect_titechappproject_data.sh)

実行:

```bash
cd /Users/sikurehayu/Desktop/app/kcm_app/ぶんせき
bash collect_titechappproject_data.sh
```

生成物:
- `artifacts/titechappproject/raw/repos.json`
- `artifacts/titechappproject/repos-summary.jsonl`
- `artifacts/titechappproject/manifests/*`
- `artifacts/titechappproject/trees/*`
- `artifacts/titechappproject/entrypoints/*`
- `artifacts/titechappproject/readme/*`

このスクリプトがやること:

1. GitHub API から組織の公開リポジトリ一覧を取得
2. 主要リポジトリのファイルツリーを取得
3. `Package.swift` / `build.gradle.kts` を保存
4. 代表エントリポイントを保存
5. README があれば保存

これで、今回の分析に使った根拠をローカルに再構成できます。

## 9. 実務的なまとめ

技術的に一番重要なのは次の 3 点です。

- 公開 GitHub の主役はアプリ本体ではなく大学システム接続 SDK
- 実装は「HTML スクレイピング + セッション維持 + Moodle API」のハイブリッド
- Swift と Kotlin の二重実装で、モバイル両 OS を支える前提が強い

つまり `TitechAppProject` は、大学システムを横断して学生向け UX を作るためのクライアント統合基盤を開発している組織です。
