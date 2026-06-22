import SwiftUI
import WebKit

struct CampusWebDestination: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let autoSearchText: String?

    init(url: URL, title: String, autoSearchText: String? = nil) {
        self.url = url
        self.title = title
        self.autoSearchText = autoSearchText
    }
}

struct CampusWebView: UIViewRepresentable {
    let url: URL
    let autoSearchText: String?
    let onLoadingChange: ((Bool) -> Void)?

    init(url: URL, autoSearchText: String? = nil, onLoadingChange: ((Bool) -> Void)? = nil) {
        self.url = url
        self.autoSearchText = autoSearchText
        self.onLoadingChange = onLoadingChange
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
            guard let autoSearchText, !autoSearchText.isEmpty, !didAutoSearch else { return }
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
            webView.evaluateJavaScript(script)
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

    var body: some View {
        NavigationView {
            ZStack {
                CampusWebView(url: destination.url, autoSearchText: destination.autoSearchText, onLoadingChange: { loading in
                    isLoading = loading
                })

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.7))
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
