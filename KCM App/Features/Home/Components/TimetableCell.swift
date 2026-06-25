import SwiftUI

struct TimetableCell: View {
    let item: ClassCell
    let isToday: Bool
    let period: Int
    let weekdayIndex: Int
    let classroomURL: String?
    let onOpenClassroomURL: (String) -> Void
    let onOpenSyllabusSearch: (String) -> Void
    let onEditClassroomURL: () -> Void
    let onAddSchedule: () -> Void

    @State private var showingActionMenu = false

    var body: some View {
        VStack(spacing: 0) {
            if item.title != nil {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accentBarColor)
                    .frame(width: 28, height: 4)
                    .padding(.top, 2)
            }

            VStack(spacing: 4) {
                if let title = item.title {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    if let room = item.room {
                        Text(room)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppTheme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(cellBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cellBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if item.title != nil {
                showingActionMenu = true
            }
        }
        .popover(isPresented: $showingActionMenu, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(spacing: 0) {
                if let classroomURL {
                    Button { showingActionMenu = false; onOpenClassroomURL(classroomURL) } label: {
                        Label("クラスルームを表示", systemImage: "video")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                    }
                    Divider()
                }
                Button { showingActionMenu = false; onEditClassroomURL() } label: {
                    Label("クラスルームを設定", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                }
                Divider()
                Button { showingActionMenu = false; if let title = item.title { onOpenSyllabusSearch(title) } } label: {
                    Label("シラバスを表示", systemImage: "book")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 220)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var cellBackground: Color {
        if isToday {
            return item.title != nil ? AppTheme.accent.opacity(0.16) : AppTheme.accent.opacity(0.04)
        }
        return item.title != nil ? AppTheme.lightBlueBorder.opacity(0.22) : Color.white.opacity(0.55)
    }

    private var cellBorder: Color {
        if isToday {
            return item.title != nil ? AppTheme.blueCardBorder.opacity(0.95) : AppTheme.lightBlueBorder.opacity(0.5)
        }
        return item.title != nil ? AppTheme.lightBlueBorder.opacity(0.85) : AppTheme.lightBlueBorder.opacity(0.45)
    }

    private var accentBarColor: Color {
        isToday ? AppTheme.accent : AppTheme.textBlue.opacity(0.8)
    }
}
