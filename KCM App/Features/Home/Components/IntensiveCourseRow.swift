import SwiftUI

struct IntensiveCourseRow: View {
    let course: IntensiveCourseCard
    let classroomURL: String?
    let onEdit: () -> Void
    let onOpenSyllabusSearch: (String) -> Void
    let onEditClassroomURL: () -> Void
    let onOpenClassroomURL: (String) -> Void

    @State private var showingActionMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(course.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if course.dateRanges.isEmpty {
                    Text("日程未入力")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange))
                } else {
                    Text("日程入力済み")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green))
                }
            }
            if !course.period.isEmpty {
                Text(course.period)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textBlue)
            }
            ForEach(course.dateRanges) { range in
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textBlue)
                    Text(range.formatted)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textBlue)
                    if let s = range.startTime, let e = range.endTime {
                        Text("  \(s)-\(e)")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }
            }
            if course.dateRanges.isEmpty {
                Text("\(course.location) \(course.instructor)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textMuted)
            } else {
                Text("\(course.location) \(course.instructor)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.lightBlueBorder.opacity(0.22))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.blueCardBorder.opacity(0.95), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            showingActionMenu = true
        }
        .popover(isPresented: $showingActionMenu, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(spacing: 0) {
                Button { showingActionMenu = false; onEdit() } label: {
                    Label("日程を編集", systemImage: "calendar.badge.clock")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                }
                Divider()
                Button { showingActionMenu = false; onEditClassroomURL() } label: {
                    Label("クラスルームを設定", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                }
                if let url = classroomURL {
                    Divider()
                    Button { showingActionMenu = false; onOpenClassroomURL(url) } label: {
                        Label("クラスルームを表示", systemImage: "video")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                    }
                }
                Divider()
                Button { showingActionMenu = false; onOpenSyllabusSearch(course.title) } label: {
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
}
