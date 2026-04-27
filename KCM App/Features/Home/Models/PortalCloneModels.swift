import SwiftUI
import WebKit

struct DayEvent: Identifiable {
    let id: String
    let title: String
    let startTime: String
    let endTime: String
    let location: String
    let classroomKey: String?
    let status: String

    // 計算済み分数（パフォーマンス最適化）
    let startMinutes: Int
    let endMinutes: Int

    init(title: String, startTime: String, endTime: String, location: String, status: String = "", classroomKey: String? = nil) {
        self.id = "\(title)|\(startTime)|\(endTime)|\(location)|\(status)"
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.classroomKey = classroomKey
        self.status = status
        self.startMinutes = Self.parseMinutes(startTime)
        self.endMinutes = Self.parseMinutes(endTime)
    }

    func layout(hourHeight: CGFloat, startHour: Int) -> (top: CGFloat, height: CGFloat) {
        let start = startMinutes - startHour * 60
        let end = endMinutes - startHour * 60
        return (
            top: CGFloat(start) * (hourHeight / 60),
            height: CGFloat(end - start) * (hourHeight / 60)
        )
    }

    private static func parseMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }
}

struct Period {
    let number: Int
    let start: String
    let end: String
}

struct WeekdayColumn {
    let label: String
}

struct ClassCell: Equatable {
    let title: String?
    let room: String?

    static var empty: Self { .init(title: nil, room: nil) }

    static func filled(_ title: String, _ room: String) -> Self {
        .init(title: title, room: room)
    }
}

struct IntensiveCourseCard: Identifiable {
    let id = UUID()
    let title: String
    let period: String
    let location: String
    let instructor: String
}

struct LessonCard: Identifiable {
    let id = UUID()
    let title: String
    let schedule: String
    let location: String
    let instructor: String
}

struct IrregularScheduleSection: Identifiable {
    let id = UUID()
    let title: String
    let courses: [IntensiveCourseCard]
}

enum NoticeSort {
    case date
    case category
}

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

    init(url: URL, autoSearchText: String? = nil) {
        self.url = url
        self.autoSearchText = autoSearchText
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
            guard webView.url != url else { return }
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(autoSearchText: autoSearchText)
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var autoSearchText: String?
        private var didAutoSearch = false

        init(autoSearchText: String?) {
            self.autoSearchText = autoSearchText
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let autoSearchText, !autoSearchText.isEmpty, !didAutoSearch else { return }
            didAutoSearch = true

            let escapedText = autoSearchText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: " ")

            let script = """
            (function() {
                var value = '\(escapedText)';
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
    }
}

struct CampusWebSheet: View {
    let destination: CampusWebDestination
    @Binding var presentedDestination: CampusWebDestination?

    var body: some View {
        NavigationView {
            CampusWebView(url: destination.url, autoSearchText: destination.autoSearchText)
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

// MARK: - 曜日ラベル（一元管理）
enum WeekdayLabels {
    static let full = ["日", "月", "火", "水", "木", "金", "土"]
    static let weekdays = ["月", "火", "水", "木", "金", "土"]
}

struct NoticeCard: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let date: String
    let category: String
    let isPinned: Bool
    let content: String
}

struct MessageThread: Identifiable, Equatable {
    enum Status {
        case online
        case offline
    }

    let id = UUID()
    let name: String
    let avatar: String
    let sharedCourse: String
    let lastMessage: String
    let lastTime: String
    let unread: Int
    let status: Status
    let messages: [ChatMessage]
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let fromMe: Bool
    let text: String
    let time: String
}

struct SettingRow {
    enum Kind {
        case toggle(Binding<Bool>)
        case link(() -> Void)
    }

    let icon: String
    let color: Color
    let title: String
    let subtitle: String?
    let kind: Kind

    static func toggle(_ icon: String, _ color: Color, _ title: String, _ subtitle: String?, _ binding: Binding<Bool>) -> Self {
        .init(icon: icon, color: color, title: title, subtitle: subtitle, kind: .toggle(binding))
    }

    static func link(_ icon: String, _ color: Color, _ title: String, _ subtitle: String?, _ action: @escaping () -> Void) -> Self {
        .init(icon: icon, color: color, title: title, subtitle: subtitle, kind: .link(action))
    }
}

extension Date {
    func startOfWeek(calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: self)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: self)) ?? self
    }
}
