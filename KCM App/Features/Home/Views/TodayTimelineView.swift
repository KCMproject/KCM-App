import SwiftUI
import Combine

struct TodayTimelineView: View {
    @ObservedObject private var viewModel = TimetableViewModel.shared
    @State private var currentTime = Date()
    @State private var selectedDate = Date()
    @State private var dateOffset = 0
    @State private var weekPageOffset = 0
    @State private var isSyncingWeekPage = false
    @State private var showingCalendar = false
    @State private var calendarMonth = Date()
    @State private var transitionDirection: TransitionDirection = .none
    @AppStorage(AppSettings.tapToSwitchDayEnabled) private var tapToSwitchDayEnabled = true
    let onToggle: () -> Void

    enum TransitionDirection: Equatable {
        case left, right, none
    }

    private let calendar = Calendar(identifier: .gregorian)
    private let hourHeight: CGFloat = 74
    private let startHour = 9
    private let endHour = 22

    private func events(for date: Date) -> [DayEvent] {
        let labels = ["日", "月", "火", "水", "木", "金", "土"]
        let calendarWeekday = Calendar.current.component(.weekday, from: date)
        let weekday = labels[calendarWeekday - 1]
        let weekdayIndex = (2...6).contains(calendarWeekday) ? calendarWeekday - 2 : -1
        
        let periods: [Period] = [
            .init(number: 1, start: "09:00", end: "10:30"),
            .init(number: 2, start: "10:40", end: "12:10"),
            .init(number: 3, start: "13:00", end: "14:30"),
            .init(number: 4, start: "14:40", end: "16:10"),
            .init(number: 5, start: "16:20", end: "17:50"),
            .init(number: 6, start: "18:00", end: "19:30")
        ]
        
        return viewModel.courses
            .filter { $0.weekday == weekday }
            .map { course in
                let p = course.period.split(separator: ",").compactMap { Int($0) }.first ?? Int(course.period) ?? 1
                let start = periods[min(max(0, p-1), periods.count-1)].start
                let end = periods[min(max(0, p-1), periods.count-1)].end
                let classroomKey = weekdayIndex >= 0 ? "\(weekdayIndex)_\(p)_\(course.title)" : nil
                return DayEvent(
                    title: course.title,
                    startTime: start,
                    endTime: end,
                    location: course.room,
                    classroomKey: classroomKey
                )
            }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                weekStripPager

                ZStack {
                    timelinePage(for: selectedDate)
                }
                .clipped()
            }

            // カレンダーポップオーバー（全体を覆う）
            if showingCalendar {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingCalendar = false
                            }
                        }

                    datePickerContent
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.2), value: showingCalendar)
            }
        }
        .background(AppTheme.pageBackground)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            currentTime = date
        }
        .onAppear {
            syncWeekPage(with: selectedDate)
        }
    }

    private func timelinePage(for date: Date) -> some View {
        timeline(for: date)
    }

    @ViewBuilder
    private func dayPage(for date: Date) -> some View {
        VStack(spacing: 0) {
            weekStrip(for: date)
            timeline(for: date)
        }
    }

    private func sideTapZone(width: CGFloat, action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: width)
            .onTapGesture(perform: action)
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingCalendar.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(dateLabel(selectedDate))
                            .font(.system(size: 17))
                            .foregroundStyle(AppTheme.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textMuted)
                            .rotationEffect(.degrees(showingCalendar ? 180 : 0))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)

                Button("今日") {
                    setDisplayedDate(Date())
                }
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(AppTheme.grayBorder, lineWidth: 1))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.border).frame(height: 1)
            }
        }
    }

    private var datePickerOverlay: some View {
        ZStack {
            // 半透明の背景（タップで閉じる）
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingCalendar = false
                    }
                }

            // カレンダーポップオーバー
            datePickerContent
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private var datePickerContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingCalendar = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .padding(.top, 12)
            .padding(.trailing, 8)

            datePickerContentInner
                .frame(height: 340)
                .clipped()
        }
        .padding()
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    @MainActor
    private var datePickerContentInner: some View {
        // UIDatePickerのinlineスタイル（サイズ変動なし）
        FixedHeightDatePicker(
            selection: Binding(
                get: { selectedDate },
                set: { newDate in
                    let normalizedDate = calendar.startOfDay(for: newDate)
                    selectedDate = normalizedDate
                    syncDateOffset(with: normalizedDate, animated: true)
                    syncWeekPage(with: normalizedDate)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingCalendar = false
                    }
                }
            ),
            range: Calendar.current.date(byAdding: .day, value: -365, to: today)!...Calendar.current.date(byAdding: .day, value: 365, to: today)!
        )
    }

    private struct FixedHeightDatePicker: UIViewRepresentable {
        @Binding var selection: Date
        var range: ClosedRange<Date>

        func makeUIView(context: Context) -> UIDatePicker {
            let picker = UIDatePicker()
            picker.datePickerMode = .date
            picker.preferredDatePickerStyle = .inline
            picker.minimumDate = range.lowerBound
            picker.maximumDate = range.upperBound
            picker.setContentHuggingPriority(.required, for: .vertical)
            picker.setContentCompressionResistancePriority(.required, for: .vertical)
            picker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)
            return picker
        }

        func updateUIView(_ uiView: UIDatePicker, context: Context) {
            if !Calendar.current.isDate(uiView.date, inSameDayAs: selection) {
                uiView.setDate(selection, animated: false)
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(binding: $selection)
        }

        class Coordinator {
            private let binding: Binding<Date>

            init(binding: Binding<Date>) {
                self.binding = binding
            }

            @objc func dateChanged(_ sender: UIDatePicker) {
                binding.wrappedValue = sender.date
            }
        }
    }

    private var weekStripPager: some View {
        TabView(selection: $weekPageOffset) {
            ForEach(-52...52, id: \.self) { offset in
                weekStrip(for: weekDate(offset: offset))
                    .tag(offset)
            }
        }
        .frame(height: 60)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: weekPageOffset) { oldValue, newValue in
            guard newValue != oldValue else { return }
            if isSyncingWeekPage {
                isSyncingWeekPage = false
                return
            }
            shiftWeek(by: newValue - oldValue)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private func weekStrip(for targetDate: Date) -> some View {
        let today = Date()
        let weekStart = targetDate.startOfWeek(calendar: calendar)
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }

        return HStack(spacing: 0) {
            ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                let selected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDate(date, inSameDayAs: today)
                let dayIndex = calendar.component(.weekday, from: date) - 1
                let textColor: Color = dayIndex == 0 ? .red.opacity(0.7) : dayIndex == 6 ? AppTheme.accent.opacity(0.8) : AppTheme.textMuted

                Button {
                    setDisplayedDate(date)
                } label: {
                    VStack(spacing: 4) {
                        Text(WeekdayLabels.full[dayIndex])
                            .font(.system(size: 12))
                            .foregroundStyle(textColor)
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 14))
                            .foregroundStyle(selected ? .white : isToday ? AppTheme.accent : AppTheme.textPrimary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(selected ? AppTheme.accent : isToday ? AppTheme.accent.opacity(0.14) : .clear)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func timeline(for date: Date) -> some View {
        let events = events(for: date)
        let slots = Array(startHour...endHour)
        let timeLabelWidth: CGFloat = 64
        let timeLabelHeight: CGFloat = 28
        let sidePadding: CGFloat = 8
        let totalHeight = CGFloat(slots.count) * hourHeight

        return ScrollView(.vertical, showsIndicators: false) {
            GeometryReader { geo in
                let cardMaxWidth = geo.size.width - (sidePadding * 2)
                let centerDeadZoneWidth: CGFloat = min(140, geo.size.width * 0.32)
                let sideZoneWidth = max((geo.size.width - centerDeadZoneWidth) / 2, 0)

                ZStack(alignment: .topLeading) {
                    // 背景のグリッド線（全幅）
                    ForEach(slots, id: \.self) { hour in
                        let y = CGFloat(hour - startHour) * hourHeight + 16
                        Capsule()
                            .fill(AppTheme.lightBlueBorder.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .frame(height: 1.5)
                            .offset(y: y)
                    }

                    // 時刻ラベル（線の真上に重ねる）
                    ForEach(slots, id: \.self) { hour in
                        let y = CGFloat(hour - startHour) * hourHeight + 16
                        Text("\(hour):00")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: timeLabelWidth, height: timeLabelHeight, alignment: .center)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(AppTheme.pageBackground)
                            )
                            .offset(y: y - (timeLabelHeight / 2))
                    }

                    // タップゾーン（日付切り替え）
                    HStack(spacing: 0) {
                        // 左ゾーン：前日へ
                        Color.clear
                            .frame(width: sideZoneWidth)
                            .contentShape(Rectangle())
                            .onTapGesture { shiftDate(by: -1) }

                        // 中央ゾーン：長押しはカードに任せる
                        Color.clear
                            .frame(width: centerDeadZoneWidth)

                        // 右ゾーン：翌日へ
                        Color.clear
                            .frame(width: sideZoneWidth)
                            .contentShape(Rectangle())
                            .onTapGesture { shiftDate(by: 1) }
                    }
                    .zIndex(-1)

                    // イベントカード（スライドアニメーション）
                    EventCardsView(
                        date: date,
                        events: events,
                        cardMaxWidth: cardMaxWidth,
                        hourHeight: hourHeight,
                        startHour: startHour,
                        timeLabelWidth: timeLabelWidth,
                        transitionDirection: transitionDirection
                    )

                    // 現在時刻の線＋ラベル（今日のみ）
                    if calendar.isDate(date, inSameDayAs: currentTime), let indicatorTop = currentIndicatorTop {
                        let indicatorLabelHeight: CGFloat = 24
                        HStack(spacing: 8) {
                            Text(currentTimeLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .frame(height: indicatorLabelHeight)
                                .background(Capsule().fill(Color.red))

                            Rectangle()
                                .fill(Color.red.opacity(0.75))
                                .frame(maxWidth: .infinity)
                                .frame(height: 1.5)
                        }
                        .frame(height: indicatorLabelHeight, alignment: .leading)
                        .offset(y: indicatorTop + 16 - (indicatorLabelHeight / 2))
                    }
                }
            }
            .frame(height: totalHeight)
            .padding(.horizontal, sidePadding)
        }
        .background(AppTheme.pageBackground)
        .refreshable {
            await PortalDataCoordinator.shared.refreshAll(showUpdateBanner: true)
        }
    }

    private var currentIndicatorTop: CGFloat? {
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        guard hour >= startHour, hour <= endHour else { return nil }
        let minutesFromStart = CGFloat((hour - startHour) * 60 + minute)
        return minutesFromStart * (hourHeight / 60)
    }

    // MARK: - DateFormatter（static でキャッシュ）
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "H:mm"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    private var currentTimeLabel: String {
        Self.timeFormatter.string(from: currentTime)
    }

    private func dateLabel(_ date: Date) -> String {
        Self.fullDateFormatter.string(from: date)
    }

    private func shiftDate(by days: Int) {
        guard let nextDate = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        let normalizedDate = calendar.startOfDay(for: nextDate)

        withAnimation(.easeInOut(duration: 0.25)) {
            transitionDirection = days > 0 ? .right : .left
            selectedDate = normalizedDate
            syncWeekPage(with: normalizedDate)
        }

        syncDateOffset(with: normalizedDate)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            transitionDirection = .none
        }
    }

    private func setDisplayedDate(_ date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        selectedDate = normalizedDate
        syncDateOffset(with: normalizedDate)
        syncWeekPage(with: normalizedDate)
    }

    private func syncDateOffset(with date: Date, animated: Bool = false) {
        guard let newOffset = calendar.dateComponents([.day], from: today, to: date).day else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                dateOffset = newOffset
            }
        } else {
            dateOffset = newOffset
        }
    }

    private func weekDate(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset * 7, to: today) ?? today
    }

    private func shiftWeek(by delta: Int) {
        guard delta != 0 else { return }
        guard let shiftedDate = calendar.date(byAdding: .day, value: delta * 7, to: selectedDate) else { return }

        withAnimation(.easeInOut(duration: 0.22)) {
            selectedDate = calendar.startOfDay(for: shiftedDate)
        }
        syncDateOffset(with: shiftedDate)
    }

    private func syncWeekPage(with date: Date) {
        let baseWeek = today.startOfWeek(calendar: calendar)
        let targetWeek = date.startOfWeek(calendar: calendar)
        let dayDelta = calendar.dateComponents([.day], from: baseWeek, to: targetWeek).day ?? 0
        let weekDelta = dayDelta / 7

        if weekPageOffset != weekDelta {
            isSyncingWeekPage = true
            weekPageOffset = weekDelta
        }
    }

}

private struct CalendarPickerView: View {
    @Binding var selectedDate: Date
    @Binding var visibleMonth: Date
    let onDateSelected: () -> Void
    let onClose: () -> Void

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        VStack(spacing: 12) {
            // 閉じるボタン
            HStack {
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            HStack {
                Button {
                    visibleMonth = calendar.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(AppTheme.textMuted)
                        .frame(width: 28, height: 28)
                }

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Button {
                    visibleMonth = calendar.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppTheme.textMuted)
                        .frame(width: 28, height: 28)
                }
            }

            HStack {
                ForEach(WeekdayLabels.full, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(monthDays.indices, id: \.self) { index in
                    if let day = monthDays[index] {
                        let date = calendar.date(from: DateComponents(
                            year: calendar.component(.year, from: visibleMonth),
                            month: calendar.component(.month, from: visibleMonth),
                            day: day
                        )) ?? selectedDate

                        Button {
                            selectedDate = date
                            onDateSelected()
                        } label: {
                            Text("\(day)")
                                .font(.system(size: 14))
                                .foregroundStyle(dayForeground(for: date))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(dayBackground(for: date))
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 288)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: visibleMonth)
    }

    private var monthDays: [Int?] {
        let components = calendar.dateComponents([.year, .month], from: visibleMonth)
        guard let firstDay = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return [] }
        let leading = calendar.component(.weekday, from: firstDay) - 1
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }

    private func dayBackground(for date: Date) -> Color {
        if calendar.isDate(date, inSameDayAs: selectedDate) {
            return AppTheme.textPrimary
        }
        if calendar.isDateInToday(date) {
            return AppTheme.grayPill
        }
        return .clear
    }

    private func dayForeground(for date: Date) -> Color {
        if calendar.isDate(date, inSameDayAs: selectedDate) {
            return .white
        }
        return AppTheme.textPrimary
    }
}

// MARK: - イベントカード（スライドアニメーション対応）
private struct EventCardsView: View {
  let date: Date
  let events: [DayEvent]
  let cardMaxWidth: CGFloat
  let hourHeight: CGFloat
  let startHour: Int
  let timeLabelWidth: CGFloat
  let transitionDirection: TodayTimelineView.TransitionDirection

  @State private var classroomURLs: [String: String] = [:]
  @State private var showingURLAlert = false
  @State private var tempURL = ""
  @State private var selectedEventID: String?

  private func loadClassroomURLs() {
    classroomURLs = PortalCacheStore.shared.loadClassroomURLs()
  }

  private func saveClassroomURLs() {
    PortalCacheStore.shared.saveClassroomURLs(classroomURLs)
  }

  private func classroomURL(for event: DayEvent) -> String? {
    if let classroomKey = event.classroomKey, let url = classroomURLs[classroomKey] {
      return url
    }
    return classroomURLs[event.id]
  }

  private func setClassroomURL(for event: DayEvent, url: String?) {
    let key = event.classroomKey ?? event.id
    if let url = url, !url.isEmpty {
      classroomURLs[key] = url
    } else {
      classroomURLs.removeValue(forKey: key)
      classroomURLs.removeValue(forKey: event.id)
    }
    saveClassroomURLs()
  }

  private func openURL(_ urlString: String) {
    if let url = URL(string: urlString) {
      UIApplication.shared.open(url)
    }
  }

  var body: some View {
    ForEach(events) { event in
      let layout = event.layout(hourHeight: hourHeight, startHour: startHour)
      VStack(alignment: .leading, spacing: 4) {
        Text(event.title)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(AppTheme.textPrimary)
        Text("\(event.startTime) - \(event.endTime)")
          .font(.system(size: 12))
          .foregroundStyle(AppTheme.textBlue)
        Text(event.location)
          .font(.system(size: 12))
          .foregroundStyle(AppTheme.textMuted)
      }
      .padding(10)
      .frame(width: cardMaxWidth, height: layout.height, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.white.opacity(0.7))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(AppTheme.blueCardBorder, lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
      .offset(x: timeLabelWidth, y: layout.top + 16)
      .contextMenu {
        if classroomURL(for: event) != nil {
          Button {
            if let url = classroomURL(for: event) {
              openURL(url)
            }
          } label: {
            Label("クラスルームを表示", systemImage: "video")
          }
        }
        Button {
          selectedEventID = event.id
          tempURL = classroomURL(for: event) ?? ""
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
        VStack(alignment: .leading, spacing: 4) {
          Text(event.title)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
          Text("\(event.startTime) - \(event.endTime)")
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.textBlue)
          Text(event.location)
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.textMuted)
        }
        .padding(10)
        .frame(width: cardMaxWidth, height: layout.height, alignment: .topLeading)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.9))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppTheme.blueCardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
      }
      .alert("クラスルームURLを設定", isPresented: $showingURLAlert) {
        TextField("URLを入力", text: $tempURL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("キャンセル", role: .cancel) {}
        Button("保存") {
          if let eventID = selectedEventID, let event = events.first(where: { $0.id == eventID }) {
            setClassroomURL(for: event, url: tempURL)
          }
        }
        Button("クリア", role: .destructive) {
          if let eventID = selectedEventID, let event = events.first(where: { $0.id == eventID }) {
            setClassroomURL(for: event, url: nil)
          }
        }
      } message: {
        Text("Google Classroom・Zoom等のURLを入力してください. ClassroomのURLはアプリではなくブラウザから取得できます。")
      }
    }
    .id(date)
    .transition(.move(edge: .trailing))
    .animation(.easeInOut(duration: 0.25), value: date)
    .onAppear {
      loadClassroomURLs()
    }
  }
}
