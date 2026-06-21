import SwiftUI

struct TabOrderSettingsList: View {
    @Binding var tabOrder: [AccountProfileCloneView.TabOrderItem]
    let onOrderChanged: ([AccountProfileCloneView.TabOrderItem]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("タブの順序（ドラッグで入れ替え）")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSoft)
                .padding(.horizontal, 4)

            List {
                ForEach(Array(tabOrder.enumerated()), id: \.element.id) { _, item in
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
                    onOrderChanged(tabOrder)
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
}
