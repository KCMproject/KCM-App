import SwiftUI

struct BoardListView: View {
    let items: [Announcement]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink {
                        BoardDetailView(item: item)
                    } label: {
                        LegacyBoardRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .navigationTitle("掲示板")
    }
}

private struct LegacyBoardRow: View {
    let item: Announcement

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                Text(item.postedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.title)
                .font(.headline)

            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Label(item.isRead ? "既読" : "未読", systemImage: item.isRead ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(item.isRead ? Color.secondary : Color.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
    }
}

#Preview {
    NavigationStack {
        BoardListView(items: MockPortalService().fetchAnnouncements())
    }
}
