import SwiftUI

struct AccountProfileCloneView: View {
    enum Tab {
        case inbox
        case settings
    }

    struct TabOrderItem: Identifiable, Codable, Hashable {
        let id: String
        let title: String
        let icon: String
    }

    @State private var activeTab: Tab = .inbox
    @State private var openThread: MessageThread?
    @AppStorage(AppSettings.pushNotificationsEnabled) private var pushEnabled = true
    @AppStorage(AppSettings.reminderEnabled) private var reminderEnabled = true
    @AppStorage(AppSettings.darkModeEnabled) private var darkEnabled = false
    @State private var tabOrder: [TabOrderItem] = [
        .init(id: "today", title: "今日", icon: "calendar"),
        .init(id: "timetable", title: "時間割", icon: "calendar.badge.clock"),
        .init(id: "board", title: "掲示板", icon: "tray.full")
    ]
    let onLogout: () -> Void
    let onTabOrderChanged: ([TabOrderItem]) -> Void
    let onNavigatePreviousTab: () -> Void
    let onNavigateNextTab: () -> Void

    private let threads: [MessageThread] = [
        .init(name: "田中 蓮", avatar: "田", sharedCourse: "線形代数学", lastMessage: "今週の課題、一緒にやらない？", lastTime: "10:32", unread: 2, status: .online, messages: [
            .init(fromMe: false, text: "線形代数の第3章ってもう終わった？", time: "10:20"),
            .init(fromMe: true, text: "まだ途中だよ〜難しいよね", time: "10:25"),
            .init(fromMe: false, text: "今週の課題、一緒にやらない？", time: "10:32")
        ]),
        .init(name: "佐藤 葵", avatar: "佐", sharedCourse: "英語コミュニケーション", lastMessage: "プレゼンのスライド共有してもいい？", lastTime: "昨日", unread: 0, status: .online, messages: [
            .init(fromMe: true, text: "英語のプレゼン、テーマ決まった？", time: "昨日 14:00"),
            .init(fromMe: false, text: "環境問題にしようと思ってる", time: "昨日 14:10"),
            .init(fromMe: false, text: "プレゼンのスライド共有してもいい？", time: "昨日 14:11")
        ]),
        .init(name: "山本 柚", avatar: "山", sharedCourse: "ゼミナール", lastMessage: "ゼミの発表、来週だよね？", lastTime: "月曜", unread: 0, status: .offline, messages: [
            .init(fromMe: false, text: "ゼミの発表、来週だよね？", time: "月曜 9:00"),
            .init(fromMe: true, text: "そうそう！準備できてる？", time: "月曜 9:05")
        ]),
        .init(name: "中村 湊", avatar: "中", sharedCourse: "プログラミング基礎", lastMessage: "エラーの解決方法わかった！", lastTime: "日曜", unread: 1, status: .online, messages: [
            .init(fromMe: false, text: "プログラミングの課題のエラーどうすればいい？", time: "日曜 20:00"),
            .init(fromMe: true, text: "どんなエラー？", time: "日曜 20:10"),
            .init(fromMe: false, text: "エラーの解決方法わかった！", time: "日曜 20:30")
        ])
    ]

    var body: some View {
        if let thread = openThread {
            ChatThreadView(thread: thread) {
                openThread = nil
            }
        } else {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        if activeTab == .inbox {
                            InboxListView(threads: threads) { thread in
                                openThread = thread
                            }
                        } else {
                            settingsView
                        }
                    }
                    .background(AppTheme.accountBackground)
                    .simultaneousGesture(accountContentSwipeGesture(width: geo.size.width))
                    .simultaneousGesture(accountEdgeSwipeGesture(width: geo.size.width))
                }
                .background(AppTheme.accountBackground)
            }
        }
    }

    private var header: some View {
        let unreadCount = threads.reduce(0) { $0 + $1.unread }

        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color(red: 0.29, green: 0.36, blue: 0.45))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text("橋")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ハシグチ")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("工学部 情報工学科 3年")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            HStack(spacing: 0) {
                accountTabButton(title: "受信箱", systemImage: "tray.full", badge: unreadCount, selected: activeTab == .inbox) {
                    activeTab = .inbox
                }
                accountTabButton(title: "設定", systemImage: "book", badge: 0, selected: activeTab == .settings) {
                    activeTab = .settings
                }
            }
        }
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private func accountTabButton(title: String, systemImage: String, badge: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14))
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(AppTheme.danger))
                            .offset(x: 6, y: -6)
                    }
                }
                Text(title)
                    .font(.system(size: 14))
            }
            .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(selected ? AppTheme.accent : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func accountContentSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let edgeThreshold: CGFloat = 28

                guard abs(horizontal) > abs(vertical), abs(horizontal) > 60 else { return }
                guard value.startLocation.x > edgeThreshold, value.startLocation.x < width - edgeThreshold else { return }

                if activeTab == .inbox {
                    if horizontal < 0 {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            activeTab = .settings
                        }
                    }
                } else {
                    if horizontal > 0 {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            activeTab = .inbox
                        }
                    }
                }
            }
    }

    private func accountEdgeSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let edgeThreshold: CGFloat = 28

                guard abs(horizontal) > abs(vertical), abs(horizontal) > 60 else { return }

                if horizontal > 0, value.startLocation.x <= edgeThreshold {
                    onNavigatePreviousTab()
                } else if horizontal < 0, value.startLocation.x >= width - edgeThreshold {
                    onNavigateNextTab()
                }
            }
    }

    private var settingsView: some View {
        VStack(spacing: 20) {
            settingsSection(
                title: "タブ",
                rows: [],
                customContent: AnyView(tabOrderSettingsList)
            )

            settingsSection(
                title: "通知",
                rows: [
                    .toggle("bell", AppTheme.accent, "プッシュ通知", nil, $pushEnabled),
                    .toggle("bell", AppTheme.favorite, "授業前リマインダー", "15分前", $reminderEnabled)
                ]
            )

            settingsSection(
                title: "表示",
                rows: [
                    .toggle("moon.fill", Color.indigo, "ダークモード", nil, $darkEnabled)
                ]
            )

            settingsSection(
                title: "アカウント",
                rows: [
                    .link("shield", Color.green, "プライバシー設定", nil, {}),
                    .link("info.circle", AppTheme.textSoft, "アプリについて", "v1.0.0", {}),
                    .link("rectangle.portrait.and.arrow.right", AppTheme.danger.opacity(0.8), "ログアウト", nil, onLogout)
                ]
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }

    private var tabOrderSettingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("タブの順序（ドラッグで入れ替え）")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSoft)
                .padding(.horizontal, 4)

            List {
                ForEach(Array(tabOrder.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.grayPill)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: item.icon)
                                    .foregroundStyle(AppTheme.accent)
                            }

                        Text(item.title)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textPrimary)

                        Spacer()

                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.white)
                }
                .onMove { source, destination in
                    tabOrder.move(fromOffsets: source, toOffset: destination)
                    onTabOrderChanged(tabOrder)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(tabOrder.count) * 60)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
        }
    }

    @ViewBuilder
    private func settingsSection(title: String, rows: [SettingRow], customContent: AnyView? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSoft)
                .padding(.horizontal, 4)

            if let customContent {
                customContent
            }

            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.grayPill)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Image(systemName: row.icon)
                                        .foregroundStyle(row.color)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.textPrimary)
                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.textMuted)
                                }
                            }

                            Spacer()

                            switch row.kind {
                            case .toggle(let binding):
                                Toggle("", isOn: binding)
                                    .labelsHidden()
                                    .tint(AppTheme.accent)
                            case .link(let action):
                                Button(action: action) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.gray.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 1)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.gray.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
            }
        }
        .background(Color.clear)
    }
}

// MARK: - 受信箱リスト

private struct InboxListView: View {
    let threads: [MessageThread]
    let onOpenThread: (MessageThread) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                    Button {
                        onOpenThread(thread)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color(red: 0.29, green: 0.36, blue: 0.45))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Text(thread.avatar)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }

                                Circle()
                                    .fill(thread.status == .online ? Color.green.opacity(0.9) : Color.gray.opacity(0.5))
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(thread.name)
                                        .font(.system(size: 14, weight: thread.unread > 0 ? .semibold : .regular))
                                        .foregroundStyle(thread.unread > 0 ? AppTheme.textPrimary : AppTheme.textSecondary)
                                    Spacer()
                                    Text(thread.lastTime)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.textMuted)
                                }

                                Text(thread.sharedCourse)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.textMuted)

                                HStack {
                                    Text(thread.lastMessage)
                                        .font(.system(size: 14, weight: thread.unread > 0 ? .medium : .regular))
                                        .foregroundStyle(thread.unread > 0 ? AppTheme.textPrimary : AppTheme.textMuted)
                                        .lineLimit(1)
                                    Spacer()
                                    if thread.unread > 0 {
                                        Text("\(thread.unread)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Circle().fill(AppTheme.accent))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white)
                    }
                    .buttonStyle(.plain)

                    if index < threads.count - 1 {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 1)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}

// MARK: - チャットスレッド

private struct ChatThreadView: View {
    let thread: MessageThread
    let onBack: () -> Void
    @State private var messages: [ChatMessage]
    @State private var draft = ""

    init(thread: MessageThread, onBack: @escaping () -> Void) {
        self.thread = thread
        self.onBack = onBack
        _messages = State(initialValue: thread.messages)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)

                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color(red: 0.29, green: 0.36, blue: 0.45))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Text(thread.avatar)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                    Circle()
                        .fill(thread.status == .online ? Color.green.opacity(0.9) : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(thread.sharedCourse)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.border).frame(height: 1)
            }

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(messages) { message in
                                HStack {
                                    if message.fromMe { Spacer() }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.text)
                                            .font(.system(size: 14))
                                            .foregroundStyle(message.fromMe ? .white : AppTheme.textPrimary)
                                        Text(message.time)
                                            .font(.system(size: 10))
                                            .foregroundStyle(message.fromMe ? Color.white.opacity(0.8) : AppTheme.textMuted)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(message.fromMe ? AppTheme.accent : .white)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(message.fromMe ? .clear : Color.gray.opacity(0.08), lineWidth: 1)
                                    )
                                    .frame(maxWidth: geo.size.width * 0.75, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    if !message.fromMe { Spacer() }
                                }
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                    .background(AppTheme.accountBackground)
                    .onAppear {
                        if let lastID = messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("メッセージを入力...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1...4)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.grayBorder, lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white)
                            )
                    )

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppTheme.accent))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.white)
            .overlay(alignment: .top) {
                Rectangle().fill(AppTheme.border).frame(height: 1)
            }
        }
        .background(AppTheme.accountBackground)
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(.init(fromMe: true, text: trimmed, time: "今"))
        draft = ""
    }
}

#Preview {
    AccountProfileCloneView(onLogout: {}) { _ in
    } onNavigatePreviousTab: {
    } onNavigateNextTab: {
    }
}
