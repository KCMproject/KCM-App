import SwiftUI

struct BoardDetailView: View {
    let item: Announcement

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.title)
                    .font(.title2.bold())

                HStack {
                    Text(item.category)
                    Spacer()
                    Text(item.postedAt)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(item.summary)
                    .font(.body)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}
