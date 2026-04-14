import SwiftUI

struct WeeklyTimetableCloneView: View {
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

    private let schedule: [[ClassCell]] = [
        [.filled("線形代数学", "A101"), .filled("物理学概論", "B203"), .empty, .filled("現代社会における情報通信技術の基礎と応用", "情報棟C401"), .filled("経済学入門", "C301")],
        [.filled("国際教養英語コミュニケーション", "B205"), .filled("情報理論", "PC-201"), .filled("化学基礎実験を含む", "D104"), .filled("英語", "B205"), .filled("哲学概論", "A203")],
        [.filled("プログラミング", "PC-301"), .filled("微分積分学", "A102"), .filled("体育実技", "体育館"), .filled("プログラミング", "PC-301"), .empty],
        [.filled("物理学実験", "E-102"), .filled("文学概論", "C205"), .filled("統計学", "A301"), .filled("物理学実験", "E-102"), .filled("社会学", "B301")],
        [.filled("ゼミナール", "R-405"), .empty, .empty, .filled("ゼミナール", "R-405"), .empty],
        [.empty, .empty, .empty, .empty, .empty]
    ]

    private let intensiveCourses: [IntensiveCourseCard] = [
        .init(title: "日本近現代史特論", period: "8/4（月）〜 8/8（金）", location: "第1講義棟 A201", instructor: "田中 教授"),
        .init(title: "データサイエンス入門", period: "9/1（月）〜 9/5（金）", location: "情報処理センター PC-401", instructor: "鈴木 准教授"),
        .init(title: "国際経営論", period: "9/16（火）〜 9/18（木）", location: "第3講義棟 C301", instructor: "Smith 講師")
    ]

    private let lessons: [LessonCard] = [
        .init(title: "ギター初級レッスン", schedule: "毎週 水曜日 18:00〜19:00", location: "音楽棟 B102", instructor: "山田 講師"),
        .init(title: "英会話セミナー", schedule: "隔週 金曜日 15:00〜16:30", location: "語学学習センター L-301", instructor: "Johnson 講師"),
        .init(title: "プログラミング実践演習", schedule: "毎月 第2土曜日 10:00〜12:00", location: "情報処理センター PC-201", instructor: "高橋 准教授")
    ]

    private var todayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
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
                            ForEach(Array(schedule[rowIndex].enumerated()), id: \.offset) { columnIndex, item in
                                let isToday = columnIndex == todayIndex
                                TimetableCell(item: item, isToday: isToday)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // レッスン等セクション
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Rectangle().fill(AppTheme.lightBlueBorder).frame(height: 1)
                            Text("レッスン等")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.textBlue)
                            Rectangle().fill(AppTheme.lightBlueBorder).frame(height: 1)
                        }
                        .padding(.top, 16)

                        ForEach(lessons) { lesson in
                            LessonRow(lesson: lesson)
                        }
                    }
                    .padding(.horizontal, 16)

                    // 集中講義セクション
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Rectangle().fill(AppTheme.lightBlueBorder).frame(height: 1)
                            Text("集中講義")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.textBlue)
                            Rectangle().fill(AppTheme.lightBlueBorder).frame(height: 1)
                        }
                        .padding(.top, 16)

                        ForEach(intensiveCourses) { course in
                            IntensiveCourseRow(course: course)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
        }
        .background(Color.white)
        .contentShape(Rectangle())
        // タップ切り替え機能は一時的に無効化
        // .onTapGesture(perform: onToggle)
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
