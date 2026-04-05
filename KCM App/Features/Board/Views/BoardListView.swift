import SwiftUI

struct BoardListView: View {
    let items: [Announcement]
    private var itemIndices: [Int] { items.enumerated().map(\.offset) }

    var body: some View {
        List {
            ForEach(itemIndices, id: \.self) { index in
                let item = items[index]
                NavigationLink {
                    BoardDetailView(item: item)
                } label: {
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
                            .foregroundStyle(item.isRead ? .secondary : .red)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("掲示板")
        .listStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        BoardListView(items: MockPortalService().fetchAnnouncements())
    }
}
