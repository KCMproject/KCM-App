import SwiftUI

struct NoticeBoardCloneView: View {
    @ObservedObject private var viewModel = NoticeBoardViewModel.shared
    @State private var searchTerm = ""
    @State private var sortBy: NoticeSort = .date
    @State private var selectedCategory = "すべて"
    @State private var favoriteIDs: Set<String> = []
    private let cacheStore = PortalCacheStore.shared

    private static let jaDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    private let categories = ["すべて", "お気に入り", "個人掲示板", "履修登録関連", "奨学金・授業料", "就職・キャリア", "施設関連", "イベント"]

    private var filteredNotices: [NoticeCard] {
        let filtered = viewModel.announcements.filter { notice in
            let matchesSearch = searchTerm.isEmpty
                || notice.title.localizedCaseInsensitiveContains(searchTerm)
                || notice.content.localizedCaseInsensitiveContains(searchTerm)
            let matchesCategory: Bool
            switch selectedCategory {
            case "すべて":
                matchesCategory = true
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
                                HStack(spacing: 4) {
                                    if category == "お気に入り" {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 12))
                                    }
                                    Text(category)
                                        .font(.system(size: 14))
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
                    if filteredNotices.isEmpty && !viewModel.isLoading {
                        VStack(spacing: 8) {
                            Image(systemName: "star")
                                .font(.system(size: 32))
                                .foregroundStyle(AppTheme.textSoft)
                            Text(selectedCategory == "お気に入り" ? "お気に入りはまだありません" : "お知らせがありません")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredNotices.enumerated()), id: \.element.id) { index, notice in
                                VStack(spacing: 0) {
                                    NoticeRow(
                                        notice: notice,
                                        isFavorite: favoriteIDs.contains(notice.id)
                                    ) {
                                        toggleFavorite(notice.id)
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
                    await PortalDataCoordinator.shared.refreshAll(showUpdateBanner: true)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.5))
                }
            }
        }
        .onAppear {
            favoriteIDs = cacheStore.loadFavoriteNoticeIDs()
        }
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
}

private struct NoticeRow: View {
    let notice: NoticeCard
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(notice.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.favorite)
                        .padding(.top, 2)
                }
            }

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

            Text(notice.content)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                onToggleFavorite()
            } label: {
                Label(isFavorite ? "解除" : "お気に入り", systemImage: isFavorite ? "star.fill" : "star")
            }
            .tint(AppTheme.favorite)
        }
    }
}
