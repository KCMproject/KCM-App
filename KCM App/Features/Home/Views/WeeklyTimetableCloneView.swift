import SwiftUI

struct WeeklyTimetableCloneView: View {
    @ObservedObject private var viewModel = TimetableViewModel.shared
    
    private enum Semester: String, CaseIterable {
        case first = "前期"
        case second = "後期"

        static var current: Self {
            let month = Calendar.current.component(.month, from: Date())
            return (4...9).contains(month) ? .first : .second
        }
    }

    @State private var selectedSemester: Semester = .current
    let onToggle: () -> Void

    private let periods: [Period] = [
        .init(number: 1, start: "09:00", end: "10:30"),
        .init(number: 2, start: "10:40", end: "12:10"),
        .init(number: 3, start: "13:00", end: "14:30"),
        .init(number: 4, start: "14:40", end: "16:10"),
        .init(number: 5, start: "16:20", end: "17:50"),
        .init(number: 6, start: "18:00", end: "19:30")
    ]

    private let dayLabels = WeekdayLabels.weekdays

    private var todayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Sunday=1, Monday=2, ..., Friday=6, Saturday=7
        return weekday >= 2 && weekday <= 6 ? weekday - 2 : -1
    }

    private var yearText: String {
        let year = Calendar.current.component(.year, from: Date())
        return "\(year)年"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Spacer()
                Menu {
                    ForEach(Semester.allCases, id: \.self) { semester in
                        Button {
                            selectedSemester = semester
                        } label: {
                            if selectedSemester == semester {
                                Label("\(yearText) \(semester.rawValue)", systemImage: "checkmark")
                            } else {
                                Text("\(yearText) \(semester.rawValue)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(yearText) \(selectedSemester.rawValue)")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(AppTheme.surface)

            // 曜日ヘッダー
            HStack(spacing: 0) {
                // 時限ラベル用のスペース
                Text("")
                    .frame(width: 48)

                ForEach(Array(dayLabels.enumerated()), id: \.offset) { index, day in
                    let isToday = index == todayIndex
                    Text(day)
                        .font(.system(size: 14, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? .white : AppTheme.textMuted)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(isToday ? AppTheme.accent : .clear))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            .background(AppTheme.surface)

            // スクロール可能な時間割グリッド
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(periods.enumerated()), id: \.offset) { rowIndex, period in
                            HStack(spacing: 0) {
                                // 時限ラベル
                                VStack(spacing: 4) {
                                    Text("\(period.number)")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(AppTheme.textSoft)
                                    VStack(spacing: 2) {
                                        Text(period.start)
                                            .font(.system(size: 9))
                                            .foregroundStyle(AppTheme.textSoft)
                                        Text("|")
                                            .font(.system(size: 9))
                                            .foregroundStyle(AppTheme.textSoft)
                                        Text(period.end)
                                            .font(.system(size: 9))
                                            .foregroundStyle(AppTheme.textSoft)
                                    }
                                }
                                .frame(width: 48)

                                // 各曜日のセル
                                ForEach(0..<5, id: \.self) { columnIndex in
                                    let isToday = columnIndex == todayIndex
                                    let item = viewModel.weeklySchedule[rowIndex][columnIndex]
                                    TimetableCell(item: item, isToday: isToday)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        // ... (レッスン等・集中講義セクション remains similar, but use empty arrays if not implemented yet)
                    }
                }
                .refreshable {
                    await viewModel.initialFetch()
                }

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.5))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
        }
    }
}

// MARK: - 時間割セル

private struct TimetableCell: View {
    let item: ClassCell
    let isToday: Bool

    var body: some View {
        VStack(spacing: 4) {
            if let title = item.title {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                if let room = item.room {
                    Text(room)
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
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
        .contextMenu {
            if item.title != nil {
                Button {
                    // シラバス表示アクション
                } label: {
                    Label("シラバスを表示", systemImage: "book")
                }
                Button {
                    // 詳細表示アクション
                } label: {
                    Label("詳細を表示", systemImage: "info.circle")
                }
                Button {
                    // 編集アクション
                } label: {
                    Label("編集", systemImage: "pencil")
                }
            }
        } preview: {
            VStack(spacing: 4) {
                if let title = item.title {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if let room = item.room {
                        Text(room)
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }
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
        }
    }

    private var cellBackground: Color {
        if isToday {
            return item.title != nil ? AppTheme.accent.opacity(0.08) : AppTheme.accent.opacity(0.04)
        }
        return item.title != nil ? .white : Color.white.opacity(0.6)
    }

    private var cellBorder: Color {
        if isToday {
            return item.title != nil ? AppTheme.blueCardBorder : AppTheme.lightBlueBorder.opacity(0.5)
        }
        return item.title != nil ? AppTheme.lightBlueBorder : AppTheme.lightBlueBorder.opacity(0.5)
    }
}

// MARK: - 集中講義カード

private struct IntensiveCourseRow: View {
    let course: IntensiveCourseCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(course.period)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textBlue)
            Text("\(course.location) \(course.instructor)")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.lightBlueBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button {
                // シラバス表示アクション
            } label: {
                Label("シラバスを表示", systemImage: "book")
            }
            Button {
                // 詳細表示アクション
            } label: {
                Label("詳細を表示", systemImage: "info.circle")
            }
            Button {
                // 編集アクション
            } label: {
                Label("編集", systemImage: "pencil")
            }
        } preview: {
            VStack(alignment: .leading, spacing: 6) {
                Text(course.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(course.period)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textBlue)
                Text("\(course.location) \(course.instructor)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.lightBlueBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - レッスン等カード

private struct LessonRow: View {
    let lesson: LessonCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lesson.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(lesson.schedule)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textBlue)
            Text("\(lesson.location) \(lesson.instructor)")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.lightBlueBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button {
                // シラバス表示アクション
            } label: {
                Label("シラバスを表示", systemImage: "book")
            }
            Button {
                // 詳細表示アクション
            } label: {
                Label("詳細を表示", systemImage: "info.circle")
            }
            Button {
                // 編集アクション
            } label: {
                Label("編集", systemImage: "pencil")
            }
        } preview: {
            VStack(alignment: .leading, spacing: 6) {
                Text(lesson.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(lesson.schedule)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textBlue)
                Text("\(lesson.location) \(lesson.instructor)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.lightBlueBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
