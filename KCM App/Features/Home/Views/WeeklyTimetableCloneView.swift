import SwiftUI

struct WeeklyTimetableCloneView: View {
    @ObservedObject private var viewModel = TimetableViewModel.shared
    @State private var classroomURLs: [String: String] = [:]
    @State private var editingClassroomKey: String?
    @State private var tempClassroomURL = ""
    
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
              let cellKey = timetableCellKey(for: item, period: period.number, weekdayIndex: columnIndex)
              TimetableCell(
                item: item,
                isToday: isToday,
                period: period.number,
                weekdayIndex: columnIndex,
                classroomURL: classroomURLs[cellKey],
                onOpenClassroomURL: openURL,
                onEditClassroomURL: {
                  requestClassroomURLEdit(for: cellKey)
                }
              )
            }
                            }
                            .padding(.vertical, 4)
                        }

                        // ... (レッスン等・集中講義セクション remains similar, but use empty arrays if not implemented yet)
                    }
                }
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
        .onAppear {
            loadClassroomURLs()
        }
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
  let onEditClassroomURL: () -> Void

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
