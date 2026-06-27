import SwiftUI

struct NoticeBoardCloneView: View {
    @ObservedObject private var viewModel = NoticeBoardViewModel.shared
    @State private var searchTerm = ""
    @State private var sortBy: NoticeSort = .date
    @State private var selectedCategory = "すべて"
    @State private var favoriteIDs: Set<String> = []
    @State private var webDestination: CampusWebDestination?
    @State private var isLoadingNotice = false
    @State private var showOpenErrorAlert = false
    private let cacheStore = PortalCacheStore.shared

    private static let jaDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    private let categories = ["すべて", "未読", "お気に入り", "授業掲示板", "個人掲示板", "全学掲示板", "コース関連", "履修登録関連", "術科試験関連"]

    private var filteredNotices: [NoticeCard] {
        let filtered = viewModel.announcements.filter { notice in
            let matchesSearch = searchTerm.isEmpty
                || notice.title.localizedCaseInsensitiveContains(searchTerm)
                || notice.content.localizedCaseInsensitiveContains(searchTerm)
            let matchesCategory: Bool
            switch selectedCategory {
            case "すべて":
                matchesCategory = true
            case "未読":
                matchesCategory = !viewModel.readIDs.contains(notice.id)
            case "お気に入り":
                matchesCategory = favoriteIDs.contains(notice.id)
            default:
                matchesCategory = notice.category == selectedCategory
            }
            return matchesSearch && matchesCategory
        }

        switch sortBy {
        case .date:
            return filtered.sorted {
                let d1 = Self.jaDateFormatter.date(from: $0.date) ?? .distantPast
                let d2 = Self.jaDateFormatter.date(from: $1.date) ?? .distantPast
                return d1 > d2
            }
        case .category:
            return filtered.sorted { $0.category < $1.category }
        }
    }

    private var shouldShowInitialLoading: Bool {
        viewModel.isLoading && viewModel.announcements.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppTheme.textMuted)
                        TextField("お知らせを検索", text: $searchTerm)
                            .textFieldStyle(.plain)
                            .foregroundStyle(AppTheme.textPrimary)
                            .font(.system(size: 14))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.grayBorder, lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                            )
                    )
                    .tint(Color.clear)

                    Menu {
                        Button("日付順") {
                            sortBy = .date
                        }
                        Button("カテゴリ順") {
                            sortBy = .category
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppTheme.grayBorder, lineWidth: 1)
                            )
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                HStack(spacing: 6) {
                                    if category == "未読" {
                                        Image(systemName: "circlebadge.fill")
                                            .font(.system(size: 12))
                                    } else if category == "お気に入り" {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 12))
                                    }
                                    Text(category)
                                        .font(.system(size: 14))
                                    Text("\(countForCategory(category))")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(chipCountForeground(category))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(chipCountBackground(category))
                                        )
                                }
                                .foregroundStyle(chipForeground(category))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(chipBackground(category)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)
                }

                if !searchTerm.isEmpty {
                    HStack(spacing: 8) {
                        Text("検索中: \"\(searchTerm)\"")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textMuted)
                        Button("クリア") {
                            searchTerm = ""
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.accent)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.white)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.border).frame(height: 1)
            }

            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    if filteredNotices.isEmpty && !shouldShowInitialLoading {
                        emptyStateView
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredNotices.enumerated()), id: \.element.id) { index, notice in
                                VStack(spacing: 0) {
                                    NoticeRow(
                                        notice: notice,
                                        isFavorite: favoriteIDs.contains(notice.id),
                                        isRead: viewModel.readIDs.contains(notice.id)
                                    ) {
                                        toggleFavorite(notice.id)
                                    } onOpen: {
                                        openNotice(notice)
                                    }
                                    
                                    if index < filteredNotices.count - 1 {
                                        Rectangle()
                                            .fill(AppTheme.border)
                                            .frame(height: 1)
                                            .padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                        .background(Color.white)
                    }
                }
                .background(AppTheme.pageBackground)
                .refreshable {
                    await PortalDataCoordinator.shared.refreshNotices(showUpdateBanner: true)
                }

                if shouldShowInitialLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.5))
                }
            }
        }
        .overlay {
            if isLoadingNotice {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.5))
            }
        }
        .onAppear {
            favoriteIDs = cacheStore.loadFavoriteNoticeIDs()
        }
        .sheet(item: $webDestination) { destination in
            CampusWebSheet(destination: destination, presentedDestination: $webDestination)
        }
        .alert("お知らせを開けませんでした", isPresented: $showOpenErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("しばらくしてからもう一度お試しください。")
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty, viewModel.announcements.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.textSoft)
                Text(errorMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                let iconName: String = {
                    if selectedCategory == "未読" { return "circlebadge" }
                    if selectedCategory == "お気に入り" { return "star" }
                    return "doc.text"
                }()
                let emptyText: String = {
                    if selectedCategory == "未読" { return "未読のお知らせはありません" }
                    if selectedCategory == "お気に入り" { return "お気に入りはまだありません" }
                    return "お知らせがありません"
                }()
                Image(systemName: iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.textSoft)
                Text(emptyText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func openNotice(_ notice: NoticeCard) {
        if !viewModel.readIDs.contains(notice.id) {
            viewModel.markAsRead(notice.id)
        }

        guard let urlString = notice.url else {
            isLoadingNotice = true
            Task {
                let resolvedURL = await viewModel.resolveNoticeURL(for: notice)
                await MainActor.run {
                    isLoadingNotice = false
                    if let resolved = resolvedURL {
                        openWebDestination(url: resolved)
                    } else {
                        showOpenErrorAlert = true
                    }
                }
            }
            return
        }

        let url: URL
        if urlString.hasPrefix("http") {
            guard let u = URL(string: urlString) else { return }
            url = u
        } else if urlString.hasPrefix("/") {
            guard let u = URL(string: "https://cs.kunitachi.ac.jp\(urlString)") else { return }
            url = u
        } else {
            guard let u = URL(string: "https://cs.kunitachi.ac.jp/campusweb/\(urlString)") else { return }
            url = u
        }

        openWebDestination(url: url)
    }

    private func openWebDestination(url: URL) {
        webDestination = CampusWebDestination(
            url: url,
            title: "掲示板詳細",
            pageValidationScript: "document.querySelector('.keiji-title, .keiji-naiyo') !== null"
        )
    }

    private func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        cacheStore.saveFavoriteNoticeIDs(favoriteIDs)
    }

    private func chipBackground(_ category: String) -> Color {
        guard selectedCategory == category else { return AppTheme.grayPill }
        return category == "お気に入り" ? AppTheme.favorite : AppTheme.accent
    }

    private func chipForeground(_ category: String) -> Color {
        selectedCategory == category ? .white : AppTheme.textPrimary
    }

    private func chipCountBackground(_ category: String) -> Color {
        selectedCategory == category ? Color.white.opacity(0.25) : AppTheme.grayPill
    }

    private func chipCountForeground(_ category: String) -> Color {
        selectedCategory == category ? .white : AppTheme.textMuted
    }

    private func countForCategory(_ category: String) -> Int {
        switch category {
        case "すべて":
            return viewModel.totalCount
        case "未読":
            return viewModel.announcements.filter { !viewModel.readIDs.contains($0.id) }.count
        case "お気に入り":
            return favoriteIDs.count
        default:
            return viewModel.count(forGenre: category)
        }
    }
}

private struct NoticeRow: View {
    let notice: NoticeCard
    let isFavorite: Bool
    let isRead: Bool
    let onToggleFavorite: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .opacity(isRead ? 0 : 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(notice.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text(notice.category)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textBlue)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textMuted)
                    Text(notice.date)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textMuted)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            VStack(spacing: 6) {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isFavorite ? AppTheme.favorite : AppTheme.textSoft)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(isFavorite ? AppTheme.favorite.opacity(0.14) : AppTheme.grayPill)
                        )
                }
                .buttonStyle(.plain)

                ZStack {
                    Circle()
                        .fill(notice.hasAttachments ? AppTheme.accent.opacity(0.12) : Color.clear)
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(notice.hasAttachments ? AppTheme.textBlue : Color.clear)
                }
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .onTapGesture {}
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }
}
