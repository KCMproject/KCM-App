import SwiftUI
import WebKit

struct CampusWebDestination: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let autoSearchText: String?
    let pageValidationScript: String?

    init(url: URL, title: String, autoSearchText: String? = nil, pageValidationScript: String? = nil) {
        self.url = url
        self.title = title
        self.autoSearchText = autoSearchText
        self.pageValidationScript = pageValidationScript
    }
}

struct CampusWebView: UIViewRepresentable {
    let url: URL
    let autoSearchText: String?
    let onLoadingChange: ((Bool) -> Void)?
    let onPageValidationFailed: (() -> Void)?
    let pageValidationScript: String?

    init(url: URL, autoSearchText: String? = nil, onLoadingChange: ((Bool) -> Void)? = nil, pageValidationScript: String? = nil, onPageValidationFailed: (() -> Void)? = nil) {
        self.url = url
        self.autoSearchText = autoSearchText
        self.onLoadingChange = onLoadingChange
        self.pageValidationScript = pageValidationScript
        self.onPageValidationFailed = onPageValidationFailed
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.autoSearchText = autoSearchText
        context.coordinator.pageValidationScript = pageValidationScript
        context.coordinator.onPageValidationFailed = onPageValidationFailed
        syncCookies {
            guard !context.coordinator.hasLoadedURL(url) else { return }
            context.coordinator.setRequestedURL(url)
            var request = URLRequest(url: url)
            request.setValue("https://cs.kunitachi.ac.jp/campusweb/campussquare.do?page=main", forHTTPHeaderField: "Referer")
            webView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(autoSearchText: autoSearchText)
        coordinator.onLoadingChange = onLoadingChange
        coordinator.pageValidationScript = pageValidationScript
        coordinator.onPageValidationFailed = onPageValidationFailed
        return coordinator
    }

    private func syncCookies(completion: @escaping () -> Void) {
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        guard !cookies.isEmpty else {
            completion()
            return
        }

        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, UIDocumentInteractionControllerDelegate {
        var autoSearchText: String?
        var onLoadingChange: ((Bool) -> Void)?
        var pageValidationScript: String?
        var onPageValidationFailed: (() -> Void)?
        private var didAutoSearch = false
        private var lastRequestedURL: URL?
        private var downloadURL: URL?
        private var documentInteractionController: UIDocumentInteractionController?

        init(autoSearchText: String?) {
            self.autoSearchText = autoSearchText
        }

        func hasLoadedURL(_ url: URL) -> Bool {
            return lastRequestedURL == url
        }

        func setRequestedURL(_ url: URL) {
            lastRequestedURL = url
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadingChange?(true)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            onLoadingChange?(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            onLoadingChange?(false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChange?(false)

            if let autoSearchText, !autoSearchText.isEmpty, !didAutoSearch {
                didAutoSearch = true
                let escapedText: String
                if let data = try? JSONSerialization.data(withJSONObject: [autoSearchText], options: []),
                   let json = String(data: data, encoding: .utf8) {
                    escapedText = String(json.dropFirst().dropLast())
                } else {
                    escapedText = "\"\""
                }
                let script = """
                (function() {
                    var value = \(escapedText);
                    var input = document.querySelector('#kaikoKamokunm, input[name="kaikoKamokunm"]');
                    if (!input) { return false; }
                    input.value = value;
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    input.dispatchEvent(new Event('change', { bubbles: true }));
                    var button = document.querySelector('input[type="button"][value*="検索"]');
                    if (button) {
                        setTimeout(function() { button.click(); }, 250);
                    }
                    return true;
                })();
                """
                webView.evaluateJavaScript(script) { [weak self] _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.runPageValidation(webView)
                    }
                }
            } else {
                runPageValidation(webView)
            }
        }

        private func runPageValidation(_ webView: WKWebView) {
            guard let script = pageValidationScript else { return }
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else { return }
                if let valid = result as? Bool, !valid {
                    self.onPageValidationFailed?()
                }
            }
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            let destinationURL = temporaryDirectory.appendingPathComponent(suggestedFilename)
            try? FileManager.default.removeItem(at: destinationURL)
            self.downloadURL = destinationURL
            completionHandler(destinationURL)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let url = downloadURL else { return }
            documentInteractionController = UIDocumentInteractionController(url: url)
            documentInteractionController?.delegate = self
            documentInteractionController?.presentPreview(animated: true)
        }
    }
}

struct CampusWebSheet: View {
    let destination: CampusWebDestination
    @Binding var presentedDestination: CampusWebDestination?

    @State private var isLoading = true
    @State private var showPageError = false

    var body: some View {
        NavigationView {
            ZStack {
                CampusWebView(
                    url: destination.url,
                    autoSearchText: destination.autoSearchText,
                    onLoadingChange: { loading in
                        isLoading = loading
                    },
                    pageValidationScript: destination.pageValidationScript,
                    onPageValidationFailed: {
                        showPageError = true
                    }
                )

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.7))
                }

                if showPageError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text("お知らせを開けませんでした")
                            .font(.system(size: 16, weight: .semibold))
                        Text("しばらくしてからもう一度お試しください。")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                }
            }
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        presentedDestination = nil
                    }
                }
            }
        }
    }
}
