# KCM App プログラム設計書

## 1. 概要

KCM App は、国立音楽大学のCampusSquareポータルから掲示板と時間割を取得し、見やすく表示するiOSアプリケーションである。

本設計書は、リファクタリング後のソフトウェア構造、各モジュールの責務、依存関係、データフローを記述する。

## 2. 設計方針

- **関心の分離（Separation of Concerns）**: 画面、ビジネスロジック、データアクセス、ネットワーク処理を明確に分離する
- **単一責任の原則（Single Responsibility Principle）**: 1つのクラス・構造体は1つの責務のみを持つ
- **プロトコル指向**: サービス層はプロトコルで抽象化し、実装の差し替えを容易にする
- **ファサードパターン**: 外部に対しては単一の `PortalClientProtocol` を提供し、内部では専責クライアントに処理を委譲する
- **不変性の活用**: モデルは原則 `let` で定義し、副作用を減らす

## 3. アーキテクチャ

本アプリケーションは、MVVM（Model-View-ViewModel）パターンを基本とし、以下の層で構成される。

```
┌─────────────────────────────────────────┐
│  Presentation Layer (Views / ViewModels) │
├─────────────────────────────────────────┤
│  Use Case / Coordinator Layer            │
├─────────────────────────────────────────┤
│  Service Layer (PortalClient)            │
├─────────────────────────────────────────┤
│  Network Layer (PortalNetworkClient)     │
├─────────────────────────────────────────┤
│  Data Layer (Parser / Cache / Keychain)  │
└─────────────────────────────────────────┘
```

### 3.1 各層の責務

| 層 | 責務 | 主なファイル |
|---|---|---|
| Presentation | UI の描画、ユーザー入力の受け付け、状態管理 | `*View.swift`, `*ViewModel.swift` |
| Coordinator | 複数 ViewModel の更新を調整 | `PortalDataCoordinator.swift` |
| Service | ポータルへの認証・データ取得の統合窓口 | `PortalClientImpl.swift` および専責クライアント |
| Network | HTTP 通信、Cookie 管理、リクエスト生成 | `PortalNetworkClient.swift`, `PortalFormClient.swift` |
| Data | HTML パース、ローカルキャッシュ、Keychain 保存 | `CampusSquareParser.swift`, `PortalCacheStore.swift`, `SavedCredentialsStore.swift` |

## 4. ディレクトリ構成

```text
KCM App/
├── App/                        # アプリ起動点、ルート画面
│   ├── AppRootView.swift
│   └── KCM_AppApp.swift
├── Core/
│   ├── Models/                 # 画面横断で使うデータモデル
│   │   ├── CampusSquareSession.swift
│   │   └── Course.swift
│   └── Services/               # portal-access 相当の窓口
│       └── Portal/
│           ├── PortalClientImpl.swift        # ファサード
│           ├── PortalClientProtocol.swift    # 公開インターフェース
│           ├── PortalAuthClient.swift        # 認証・セッション
│           ├── PortalAnnouncementClient.swift # 掲示板
│           ├── PortalTimetableClient.swift   # 時間割
│           ├── PortalPDFClient.swift         # PDF・ユーザー名
│           ├── PortalFormClient.swift        # フォームPOST
│           ├── PortalNetworkClient.swift     # 基盤通信
│           ├── PortalClientHelper.swift      # URL・ページング等の共通処理
│           ├── CampusSquareParser.swift      # 業務パース
│           └── HTMLParserHelpers.swift       # HTMLタグ操作の低レベルヘルパー
├── Features/
│   ├── Auth/                   # ログイン、セッション管理
│   │   ├── Models/
│   │   │   ├── CampusSquareCredentials.swift
│   │   │   ├── CampusSquareLoginError.swift
│   │   │   └── ValidationResult.swift
│   │   ├── ViewModels/
│   │   │   └── LoginViewModel.swift
│   │   └── Views/
│   │       └── LoginView.swift
│   └── Home/                   # ホーム（今日/時間割/掲示板/アカウント）
│       ├── Components/         # 画面共通コンポーネント
│       │   └── CampusWebView.swift
│       ├── Models/
│       │   └── PortalCloneModels.swift
│       ├── ViewModels/
│       │   ├── NoticeBoardViewModel.swift
│       │   ├── PortalDataCoordinator.swift
│       │   └── TimetableViewModel.swift
│       └── Views/
│           ├── AccountProfileCloneView.swift
│           ├── NoticeBoardCloneView.swift
│           ├── PortalCloneView.swift
│           ├── TodayTimelineView.swift
│           └── WeeklyTimetableCloneView.swift
└── Shared/
    ├── Components/             # 共通 UI コンポーネント
    ├── DesignSystem/           # 色やテーマ
    └── Utils/                  # 共通ユーティリティ
        ├── AppBannerCenter.swift
        ├── AppSettings.swift
        ├── DeviceAuthenticationManager.swift
        ├── PortalCacheStore.swift
        └── SavedCredentialsStore.swift
```

## 5. 主要コンポーネント

### 5.1 PortalClientImpl（ファサード）

`PortalClientProtocol` を実装し、アプリケーション全体からの統合窓口となる。

```swift
final class PortalClientImpl: PortalClientProtocol {
    private let networkClient: PortalNetworkClient
    private let authClient: PortalAuthClient
    private let announcementClient: PortalAnnouncementClient
    private let timetableClient: PortalTimetableClient
    private let pdfClient: PortalPDFClient
}
```

各 `PortalClientProtocol` メソッドは、対応する専責クライアントに処理を委譲する。

### 5.2 専責クライアント

| クラス | 責務 |
|---|---|
| `PortalAuthClient` | ログイン、ログアウト、セッション検証、自動再ログイン |
| `PortalAnnouncementClient` | 掲示板一覧取得、添付ファイル取得、詳細URL解決、ページング |
| `PortalTimetableClient` | スケジュール管理（月次）と週間時間割（RSW）の取得 |
| `PortalPDFClient` | 成績通知書PDFダウンロード、ユーザー名取得 |
| `PortalFormClient` | ポータルへのフォームPOST送信（HTML/Data両対応） |

### 5.3 共通ヘルパー

| クラス | 責務 |
|---|---|
| `PortalClientHelper` | URL 解決、ページ検証、ページング抽出、フォームエンコード、お知らせソート |
| `HTMLParserHelpers` | HTML タグの抽出・内外部取得・属性値取得・エンティティデコード |

### 5.4 パーサー

| クラス | 責務 |
|---|---|
| `CampusSquareParser` | ポータル固有の業務ロジックに基づくHTMLパース（お知らせ、時間割、ユーザー名等） |
| `HTMLParserHelpers` | 汎用的なHTML文字列操作（タグの抽出・除去等） |

## 6. 依存関係

```
Views / ViewModels
    │
    ▼
PortalDataCoordinator
    │
    ▼
PortalClientImpl (PortalClientProtocol)
    │
    ├── PortalAuthClient
    │       └── PortalNetworkClient
    │
    ├── PortalAnnouncementClient
    │       ├── PortalNetworkClient
    │       ├── PortalAuthClient
    │       └── PortalFormClient
    │
    ├── PortalTimetableClient
    │       ├── PortalNetworkClient
    │       └── PortalAuthClient
    │
    └── PortalPDFClient
            ├── PortalNetworkClient
            ├── PortalAuthClient
            ├── PortalFormClient
            └── PortalTimetableClient

CampusSquareParser
    └── HTMLParserHelpers
```

## 7. データフロー

### 7.1 ログインからデータ表示まで

1. `LoginView` が `LoginViewModel.login()` を呼び出す
2. `LoginViewModel` は `PortalClientFactory.makeLoginService()` から取得した `PortalClientProtocol` を経由してログイン
3. `PortalClientImpl` は `PortalAuthClient` に認証を委譲
4. 認証成功後、`PortalDataCoordinator.refreshAll()` が各 ViewModel のデータ更新を調整
5. 各 ViewModel は `PortalClientImpl` を経由して専責クライアントを呼び出し、データを取得
6. 取得したデータは `PortalCacheStore` に保存され、`@Published` プロパティを通じて View に反映

### 7.2 自動再ログイン

1. `PortalAuthClient.executeWithAutoRelogin` が各専責クライアントの操作をラップ
2. 操作中に `sessionExpired` が発生すると、`SavedCredentialsStore` から資格情報を取得
3. 資格情報があれば `performLogin` で再ログインし、操作を再試行
4. 再ログインに失敗した場合は `sessionExpired` を再スロー

## 8. セキュリティ設計

- **資格情報の保存**: `SavedCredentialsStore` が Keychain に JSON 形式で保存
  - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` を指定
  - `kSecAttrSynchronizable` を `false` に設定し、iCloud 同期を防止
  - 旧形式（平文）からの移行対応を実装
- **通信**: HTTPS を使用し、Cookie は共有ストレージで管理
- **ログ出力**: 認証情報・セッション情報・Cookie を出力する `print` 文は削除済み

## 9. 今後の拡張ポイント

- 各専責クライアントに対する Unit Test の追加
- `PortalClientProtocol` のモック実装を本格的に活用したテスト
- エラー型のさらなる細分化（`PortalError` の導入検討）
- View 層の肥大化しているファイル（`TodayTimelineView.swift` 等）のコンポーネント分割
