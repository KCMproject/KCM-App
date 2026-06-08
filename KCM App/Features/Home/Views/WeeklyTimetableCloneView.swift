import SwiftUI
import UIKit

struct WeeklyTimetableCloneView: View {
    @ObservedObject private var viewModel = TimetableViewModel.shared
    @State private var classroomURLs: [String: String] = [:]
    @State private var editingClassroomKey: String?
    @State private var tempClassroomURL = ""
    @State private var webDestination: CampusWebDestination?
    @State private var showingScheduleSheet = false
    @State private var selectedCourseTitle = ""
    
    let onToggle: () -> Void

    private let periods: [Period] = [
        .init(number: 1, start: "09:00", end: "10:30"),
        .init(number: 2, start: "10:40", end: "12:10"),
        .init(number: 3, start: "13:00", end: "14:30"),
        .init(number: 4, start: "14:40", end: "16:10"),
        .init(number: 5, start: "16:20", end: "17:50"),
        .init(number: 6, start: "18:00", end: "19:30")
    ]

    private var dayLabels: [String] {
        viewModel.hasSaturdayClass ? WeekdayLabels.weekdays : Array(WeekdayLabels.weekdays.prefix(5))
    }

    private var todayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Sunday=1, Monday=2, ..., Friday=6, Saturday=7
        return (2...7).contains(weekday) ? weekday - 2 : -1
    }

    private var yearText: String {
        let year = Calendar.current.component(.year, from: Date())
        return "\(year)年"
    }

    private func timetableCellKey(for item: ClassCell, period: Int, weekdayIndex: Int) -> String {
        "\(weekdayIndex)_\(period)_\(item.title ?? "")"
    }

    private func loadClassroomURLs() {
        classroomURLs = PortalCacheStore.shared.loadClassroomURLs()
    }

    private func saveClassroomURLs() {
        PortalCacheStore.shared.saveClassroomURLs(classroomURLs)
    }

    private func requestClassroomURLEdit(for key: String) {
        tempClassroomURL = classroomURLs[key] ?? ""
        DispatchQueue.main.async {
            editingClassroomKey = key
        }
    }

    private func saveClassroomURL() {
        guard let key = editingClassroomKey else { return }
        let trimmedURL = tempClassroomURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            classroomURLs.removeValue(forKey: key)
        } else {
            classroomURLs[key] = trimmedURL
        }
        saveClassroomURLs()
    }

    private func clearClassroomURL() {
        guard let key = editingClassroomKey else { return }
        classroomURLs.removeValue(forKey: key)
        saveClassroomURLs()
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func openSyllabusSearch(for title: String) {
        UIPasteboard.general.string = title
        guard let url = URL(string: "https://cs.kunitachi.ac.jp/campusweb/campussquare.do?_flowId=SBW3701300-flow&link=menu-link-mf-164899") else { return }
        webDestination = CampusWebDestination(url: url, title: "シラバス参照", autoSearchText: title)
    }

    private var hasVisibleSchedule: Bool {
        weeklyScheduleHasContent(viewModel.weeklySchedule)
    }

    private var isShowingClassroomAlert: Binding<Bool> {
        Binding(
            get: { editingClassroomKey != nil },
            set: { isPresented in
                if !isPresented {
                    editingClassroomKey = nil
                    tempClassroomURL = ""
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Spacer()
                Menu {
                    ForEach(TimetableSemester.allCases, id: \.self) { semester in
                        Button {
                            viewModel.selectSemester(semester)
                        } label: {
                            if viewModel.selectedSemester == semester {
                                Label("\(yearText) \(semester.displayName)", systemImage: "checkmark")
                            } else {
                                Text("\(yearText) \(semester.displayName)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(yearText) \(viewModel.selectedSemester.displayName)")
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
                                ForEach(0..<dayLabels.count, id: \.self) { columnIndex in
                                    let isToday = columnIndex == todayIndex
                                    let item = viewModel.weeklySchedule[rowIndex][columnIndex]
                                    let cellKey = timetableCellKey(for: item, period: period.number, weekdayIndex: columnIndex)
                                    TimetableCell(
                                        item: item,
                                        isToday: isToday,
                                        period: period.number,
                                        weekdayIndex: columnIndex,
                                        classroomURL: classroomURLs[cellKey],
                                        onOpenClassroomURL: openURL,
                                        onOpenSyllabusSearch: openSyllabusSearch,
                                        onEditClassroomURL: {
                                            requestClassroomURLEdit(for: cellKey)
                                        },
                                        onAddSchedule: {
                                            if let title = item.title {
                                                selectedCourseTitle = title
                                                showingScheduleSheet = true
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        // 集中講義セクション
                        if !viewModel.intensiveCourses.isEmpty {
                            VStack(spacing: 12) {
                                // セクションタイトル（左右に線）
                                HStack(spacing: 12) {
                                    Rectangle()
                                        .fill(AppTheme.border)
                                        .frame(height: 1)
                                    Text("集中講義")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppTheme.textMuted)
                                    Rectangle()
                                        .fill(AppTheme.border)
                                        .frame(height: 1)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 16)

                                ForEach(viewModel.intensiveCourses) { course in
                                    IntensiveCourseRow(course: course, onEdit: {
                                        selectedCourseTitle = course.title
                                        showingScheduleSheet = true
                                    })
                                }
                            }
                            .padding(.bottom, 24)
                        }
                    }
                }
                .refreshable {
                    await PortalDataCoordinator.shared.refreshWeeklyTimetable(showUpdateBanner: true)
                }

                if viewModel.isLoading && !hasVisibleSchedule {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.5))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
        }
        .alert("クラスルームURLを設定", isPresented: isShowingClassroomAlert) {
            TextField("URLを入力", text: $tempClassroomURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("キャンセル", role: .cancel) {}
            Button("保存") {
                saveClassroomURL()
            }
            Button("クリア", role: .destructive) {
                clearClassroomURL()
            }
        } message: {
            Text("Google Classroom・Zoom等のURLを入力してください. ClassroomのURLはアプリではなくブラウザから取得できます。")
        }
        .sheet(item: $webDestination) { destination in
            CampusWebSheet(destination: destination, presentedDestination: $webDestination)
        }
        .sheet(isPresented: $showingScheduleSheet) {
            IntensiveScheduleSheet(
                courseTitle: selectedCourseTitle,
                intensiveCourses: $viewModel.intensiveCourses
            )
            .presentationDetents([.height(480)])
        }
        .onAppear {
            viewModel.loadCachedData()
            loadClassroomURLs()
        }
    }
}

private func weeklyScheduleHasContent(_ schedule: [[ClassCell]]) -> Bool {
    schedule.contains { row in
        row.contains { $0.title != nil }
    }
}

// MARK: - 時間割セル

private struct TimetableCell: View {
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
    .contextMenu {
      if item.title != nil {
        if let classroomURL {
          Button {
            onOpenClassroomURL(classroomURL)
          } label: {
            Label("クラスルームを表示", systemImage: "video")
          }
        }
        Button {
          onEditClassroomURL()
        } label: {
          Label("クラスルームを設定", systemImage: "link.badge.plus")
        }
        Divider()
        Button {
          if let title = item.title {
            onOpenSyllabusSearch(title)
          }
        } label: {
          Label("シラバスを表示", systemImage: "book")
        }
        Button {
          // 詳細表示アクション
        } label: {
          Label("詳細を表示", systemImage: "info.circle")
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
    .contentShape(Rectangle())
    .onTapGesture {
      if item.title != nil {
        showingActionMenu = true
      }
    }
    .confirmationDialog("", isPresented: $showingActionMenu, titleVisibility: .hidden) {
      if let classroomURL {
        Button {
          onOpenClassroomURL(classroomURL)
        } label: {
          Label("クラスルームを表示", systemImage: "video")
        }
      }
      Button {
        onEditClassroomURL()
      } label: {
        Label("クラスルームを設定", systemImage: "link.badge.plus")
      }
      Button {
        if let title = item.title {
          onOpenSyllabusSearch(title)
        }
      } label: {
        Label("シラバスを表示", systemImage: "book")
      }
      Button {
        // 詳細表示アクション
      } label: {
        Label("詳細を表示", systemImage: "info.circle")
      }
      Button("キャンセル", role: .cancel) {}
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

// MARK: - 集中講義カード

private struct IntensiveCourseRow: View {
  let course: IntensiveCourseCard
  let onEdit: () -> Void

  @State private var classroomURLs: [String: String] = [:]
  @State private var showingURLAlert = false
  @State private var tempURL = ""

  private var cellKey: String {
    "\(course.title)_\(course.period)"
  }

  private func loadClassroomURLs() {
    classroomURLs = PortalCacheStore.shared.loadClassroomURLs()
  }

  private func saveClassroomURLs() {
    PortalCacheStore.shared.saveClassroomURLs(classroomURLs)
  }

  private func classroomURL() -> String? {
    classroomURLs[cellKey]
  }

  private func setClassroomURL(url: String?) {
    if let url = url, !url.isEmpty {
      classroomURLs[cellKey] = url
    } else {
      classroomURLs.removeValue(forKey: cellKey)
    }
    saveClassroomURLs()
  }

  private func openURL(_ urlString: String) {
    if let url = URL(string: urlString) {
      UIApplication.shared.open(url)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top) {
        Text(course.title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppTheme.textPrimary)
        Spacer()
        // 日程インジケーター
        if course.dates.isEmpty {
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
      Text("\(course.location) \(course.instructor)")
        .font(.system(size: 12))
        .foregroundStyle(AppTheme.textMuted)
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
    .contextMenu {
      Button {
        onEdit()
      } label: {
        Label("日程を編集", systemImage: "calendar.badge.clock")
      }
      if classroomURL() != nil {
        Button {
          if let url = classroomURL() {
            openURL(url)
          }
        } label: {
          Label("クラスルームを表示", systemImage: "video")
        }
      }
      Button {
        tempURL = classroomURL() ?? ""
        showingURLAlert = true
      } label: {
        Label("クラスルームを設定", systemImage: "link.badge.plus")
      }
      Divider()
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
      .background(AppTheme.lightBlueBorder.opacity(0.22))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(AppTheme.blueCardBorder.opacity(0.95), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .contentShape(Rectangle())
    .onTapGesture {
      onEdit()
    }
    .alert("クラスルームURLを設定", isPresented: $showingURLAlert) {
      TextField("URLを入力", text: $tempURL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("キャンセル", role: .cancel) {}
      Button("保存") {
        setClassroomURL(url: tempURL)
      }
      Button("クリア", role: .destructive) {
        setClassroomURL(url: nil)
      }
    } message: {
        Text("Google Classroom・Zoom等のURLを入力してください. ClassroomのURLはアプリではなくブラウザから取得できます。")
    }
    .onAppear {
      loadClassroomURLs()
    }
  }
}

// MARK: - レッスン等カード

private struct LessonRow: View {
  let lesson: LessonCard

  @State private var classroomURLs: [String: String] = [:]
  @State private var showingURLAlert = false
  @State private var tempURL = ""

  private var cellKey: String {
    "\(lesson.title)_\(lesson.schedule)"
  }

  private func loadClassroomURLs() {
    classroomURLs = PortalCacheStore.shared.loadClassroomURLs()
  }

  private func saveClassroomURLs() {
    PortalCacheStore.shared.saveClassroomURLs(classroomURLs)
  }

  private func classroomURL() -> String? {
    classroomURLs[cellKey]
  }

  private func setClassroomURL(url: String?) {
    if let url = url, !url.isEmpty {
      classroomURLs[cellKey] = url
    } else {
      classroomURLs.removeValue(forKey: cellKey)
    }
    saveClassroomURLs()
  }

  private func openURL(_ urlString: String) {
    if let url = URL(string: urlString) {
      UIApplication.shared.open(url)
    }
  }

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
        if classroomURL() != nil {
          Button {
            if let url = classroomURL() {
              openURL(url)
            }
          } label: {
            Label("クラスルームを表示", systemImage: "video")
          }
        }
        Button {
          tempURL = classroomURL() ?? ""
          DispatchQueue.main.async {
            showingURLAlert = true
          }
        } label: {
          Label("クラスルームを設定", systemImage: "link.badge.plus")
        }
        Divider()
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
    .alert("クラスルームURLを設定", isPresented: $showingURLAlert) {
      TextField("URLを入力", text: $tempURL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("キャンセル", role: .cancel) {}
      Button("保存") {
        setClassroomURL(url: tempURL)
      }
      Button("クリア", role: .destructive) {
        setClassroomURL(url: nil)
      }
    } message: {
        Text("Google Classroom・Zoom等のURLを入力してください. ClassroomのURLはアプリではなくブラウザから取得できます。")
    }
    .onAppear {
      loadClassroomURLs()
    }
  }
}

// MARK: - 集中講義日程管理シート

private struct IntensiveScheduleSheet: View {
    let courseTitle: String
    @Binding var intensiveCourses: [IntensiveCourseCard]
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingAddSheet = false
    @State private var refreshID = UUID()
    
    private var existingCourse: IntensiveCourseCard? {
        intensiveCourses.first { $0.title == courseTitle }
    }
    
    private var scheduleRanges: [(id: String, dates: [String], startTime: String?, endTime: String?)] {
        guard let course = existingCourse, !course.dates.isEmpty else { return [] }
        // 連続した日程を範囲にグループ化
        let sorted = course.dates.sorted()
        var ranges: [(id: String, dates: [String], startTime: String?, endTime: String?)] = []
        var currentRange: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for dateStr in sorted {
            if formatter.date(from: dateStr) != nil {
                if let lastStr = currentRange.last,
                   let lastDate = formatter.date(from: lastStr),
                   let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: lastDate),
                   formatter.string(from: nextDay) == dateStr {
                    currentRange.append(dateStr)
                } else {
                    if !currentRange.isEmpty {
                        ranges.append((id: currentRange.first ?? dateStr, dates: currentRange, startTime: existingCourse?.startTime, endTime: existingCourse?.endTime))
                    }
                    currentRange = [dateStr]
                }
            }
        }
        if !currentRange.isEmpty {
            ranges.append((id: currentRange.first ?? UUID().uuidString, dates: currentRange, startTime: existingCourse?.startTime, endTime: existingCourse?.endTime))
        }
        return ranges
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("登録済み日程")) {
                    if scheduleRanges.isEmpty {
                        Text("まだ日程が追加されていません")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textMuted)
                    } else {
                        ForEach(Array(scheduleRanges.enumerated()), id: \.element.id) { index, range in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatDateRange(range.dates))
                                        .font(.system(size: 14, weight: .semibold))
                                    if let start = range.startTime, let end = range.endTime {
                                        Text("\(start) 〜 \(end)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.textBlue)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    deleteRange(range.dates)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .id(refreshID)
                    }
                }
                
                Section {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("日程を追加", systemImage: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .navigationTitle("日程を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: {
            refreshID = UUID()
        }) {
            IntensiveScheduleAddSheet(
                courseTitle: courseTitle,
                intensiveCourses: $intensiveCourses
            )
            .presentationDetents([.height(420)])
        }
    }
    
    private func formatDateRange(_ dates: [String]) -> String {
        guard let first = dates.first, let last = dates.last else { return "" }
        if first == last { return first }
        return "\(first) 〜 \(last)"
    }
    
    private func deleteRange(_ datesToDelete: [String]) {
        if let index = intensiveCourses.firstIndex(where: { $0.title == courseTitle }) {
            var updated = intensiveCourses[index]
            updated.dates.removeAll { datesToDelete.contains($0) }
            // 配列全体を新しいインスタンスに置き換えてSwiftUIに変更を検知させる
            var newCourses = intensiveCourses
            newCourses[index] = updated
            intensiveCourses = newCourses
            PortalCacheStore.shared.saveIntensiveCourses(intensiveCourses)
        }
    }
}

// MARK: - 日程追加用シート（単一範囲）

private struct IntensiveScheduleAddSheet: View {
    let courseTitle: String
    @Binding var intensiveCourses: [IntensiveCourseCard]
    @Environment(\.dismiss) private var dismiss
    
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var startTimeText = "09:00"
    @State private var endTimeText = "17:00"
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("日程範囲")) {
                    DatePicker("開始日", selection: $startDate, displayedComponents: .date)
                    DatePicker("終了日", selection: $endDate, displayedComponents: .date)
                }
                
                Section(header: Text("時間")) {
                    HStack {
                        TextField("開始", text: $startTimeText)
                            .keyboardType(.numbersAndPunctuation)
                        Text("〜")
                        TextField("終了", text: $endTimeText)
                            .keyboardType(.numbersAndPunctuation)
                    }
                }
            }
            .navigationTitle("日程を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        addSchedule()
                    }
                }
            }
        }
    }
    
    private func addSchedule() {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var newDates: [String] = []
        var current = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        while current <= end {
            newDates.append(formatter.string(from: current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        let trimmedStart = startTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnd = endTimeText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let index = intensiveCourses.firstIndex(where: { $0.title == courseTitle }) {
            var updated = intensiveCourses[index]
            // 既存の日程とマージ（重複排除）
            var mergedDates = Set(updated.dates)
            mergedDates.formUnion(newDates)
            updated.dates = Array(mergedDates).sorted()
            updated.startTime = trimmedStart.isEmpty ? nil : trimmedStart
            updated.endTime = trimmedEnd.isEmpty ? nil : trimmedEnd
            // 配列全体を新しいインスタンスに置き換えてSwiftUIに変更を検知させる
            var newCourses = intensiveCourses
            newCourses[index] = updated
            intensiveCourses = newCourses
            PortalCacheStore.shared.saveIntensiveCourses(intensiveCourses)
        }

        dismiss()
    }
}
