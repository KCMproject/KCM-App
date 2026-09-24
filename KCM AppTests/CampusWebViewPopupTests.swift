import SwiftUI
import WebKit
import XCTest

@testable import KCM_App

/// CampusSquare はシラバス詳細などを `window.open` の別ウィンドウで開く。
/// アプリ内 WebView ではポップアップ要求を同じ WebView に読み込んで遷移させる必要がある。
@MainActor
final class CampusWebViewPopupTests: XCTestCase {
    private var window: UIWindow?
    private var fixtureDirectory: URL!

    override func setUp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CampusWebViewPopupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.parentHTML.write(to: directory.appendingPathComponent("parent.html"), atomically: true, encoding: .utf8)
        try Self.popupHTML.write(to: directory.appendingPathComponent("popup.html"), atomically: true, encoding: .utf8)
        fixtureDirectory = directory
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    /// 検索結果一覧の「参照」ボタン（`window.open`）でシラバス詳細が開くこと
    func testWindowOpenLoadsInSameWebView() async throws {
        let webView = try await loadedWebView()

        try await webView.evaluateJavaScript("document.querySelector('[data-role=open-syllabus]').click()")

        try await waitForPopup(in: webView)
    }

    /// `target="_blank"` のリンクでもシラバス詳細が開くこと
    func testTargetBlankLinkLoadsInSameWebView() async throws {
        let webView = try await loadedWebView()

        try await webView.evaluateJavaScript("document.querySelector('[data-role=blank-link]').click()")

        try await waitForPopup(in: webView)
    }

    // MARK: - Helpers

    private func loadedWebView() async throws -> WKWebView {
        let pageURL = fixtureDirectory.appendingPathComponent("parent.html")
        let hosting = UIHostingController(rootView: CampusWebView(url: pageURL))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 780))
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.frame = window.bounds
        hosting.view.layoutIfNeeded()
        self.window = window

        let webView = try XCTUnwrap(Self.findWebView(in: hosting.view))
        try await wait("検索結果ページの読み込み", timeout: 10) { webView.url == pageURL && !webView.isLoading }
        return webView
    }

    private func waitForPopup(in webView: WKWebView) async throws {
        let popupURL = fixtureDirectory.appendingPathComponent("popup.html")
        try await wait("ポップアップの読み込み", timeout: 10) { webView.url == popupURL && !webView.isLoading }
        let popup = try await webView.evaluateJavaScript("document.getElementById('popup') !== null") as? Bool
        XCTAssertEqual(popup, true, "ポップアップの内容が同じ WebView に読み込まれていない")
        XCTAssertEqual(webView.backForwardList.backList.count, 1, "ポップアップが重複して読み込まれている")
    }

    private func wait(_ label: String, timeout: TimeInterval, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("\(label)が \(timeout) 秒以内に完了しなかった")
    }

    private static func findWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let webView = findWebView(in: subview) { return webView }
        }
        return nil
    }

    private static let parentHTML = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script>
    function refer() {
        // CampusSquare のシラバス表示（syRefer / refer）と同じ仕組み
        SubWin = window.open('popup.html', 'SyllabusWindow', 'width=750,height=650,location=0,menubar=0,scrollbars=1,resizable=1,toolbar=1');
    }
    </script>
    </head>
    <body>
    <input type="button" name="refer" value="参照" data-role="open-syllabus" onclick="refer();">
    <a href="popup.html" target="_blank" data-role="blank-link">シラバス</a>
    </body>
    </html>
    """

    private static let popupHTML = """
    <!DOCTYPE html>
    <html>
    <body>
    <div id="popup">シラバス詳細</div>
    </body>
    </html>
    """
}
