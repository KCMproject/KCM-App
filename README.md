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

## 現在の状態

- ログイン画面の雛形あり
- 掲示板一覧/詳細の雛形あり
- 時間割一覧/授業詳細の雛形あり
- `MockPortalService` でダミーデータ表示

次の実装候補は `PortalSessionManaging` を本物のログイン・取得処理に差し替えることです。
