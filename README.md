# KCM App

大学ポータルの掲示板と時間割を見やすく確認するための iOS アプリです。

## ディレクトリ構成

```text
KCM App/
├── App/                    # アプリ起動点、ルート画面、タブ構成
├── Core/
│   ├── Models/             # 画面横断で使うデータモデル
│   └── Services/           # portal-access 相当の窓口
├── Features/
│   ├── Auth/               # ログイン、セッション管理
│   ├── Board/              # 掲示板一覧・詳細
│   └── Timetable/          # 時間割一覧・授業詳細
├── Shared/
│   ├── Components/         # 共通 UI コンポーネント
│   └── DesignSystem/       # 色やテーマ
└── Assets.xcassets
```

## 担当分担の目安

- ハシグチ: `KCM App/Shared`, `KCM App/Features/*/Views`
- タナカ: `KCM App/Features/Auth`, `KCM App/Core/Services`
- トクダ: `KCM App/Core/Models`, `KCM App/Core/Services`, 将来の parser/portal-access 実装

## 開発ルール

- 画面は `Features/<Feature>/Views` に置く
- 認証や取得処理は `Core/Services` か各 Feature 配下の ViewModel に寄せる
- モデルを増やすときは複数画面で使うものを `Core/Models` に置く
- モック実装から始めて、本実装へ差し替えるときもプロトコルは維持する

## 実機ビルド設定

- 共有設定は `Config/App.shared.xcconfig` にあります
- 各自 `Config/Local.example.xcconfig` を `Config/Local.xcconfig` としてコピーして使ってください
- `Local.xcconfig` は Git 管理外です
- 実機ビルドしたい人は自分の `DEVELOPMENT_TEAM` と `PRODUCT_BUNDLE_IDENTIFIER` を `Local.xcconfig` に入れてください

## お知らせ配信

ポータル仕様変更などでアプリが壊れたとき、アプリ更新なしで全ユーザーにお知らせを届けられます。

### 更新方法

1. GitHub のウェブ編集で直下の `announcements.json` を開く
2. `announcements.template.json` の中身をコピーして `announcements` 配列に貼り付け、文言を書き換える
3. コミットする（反映まで数分）

### フィールド

| キー | 説明 |
| --- | --- |
| `id` | 一意の識別子（`YYYY-MM-DD-内容` 推奨）。同じIDは1ユーザーにつき1回だけ表示 |
| `level` | `info` / `warning` / `critical`（色とアイコン・見出しが変わる） |
| `title` | モーダルの見出し |
| `body` | 本文（`\n` で改行） |
| `date` | 表示用の日付（`YYYY-MM-DD`）。新しい順に表示される |
| `active` | `false` にすると引き上げ（再コミットで取り消し） |

### 仕組み

- アプリは起動時とフォアグラウンド復帰時に `raw.githubusercontent.com` から取得します
- 未読のお知らせはソシャゲ風の最前面モーダルで表示され、×で閉じると既読になります
- アカウントタブの「お知らせ通知」をONにしているユーザーにはローカル通知も飛びます
- 取得失敗時はサイレントに無視され、アプリ本体の動作には一切影響しません

## 現在の状態

- ログイン画面の雛形あり
- 掲示板一覧/詳細の雛形あり
- 時間割一覧/授業詳細の雛形あり
- `MockPortalService` でダミーデータ表示

次の実装候補は `PortalSessionManaging` を本物のログイン・取得処理に差し替えることです。
