import SwiftUI
import Combine
import UIKit

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
    @State private var selectedActionEvent: DayEvent?
    @State private var webDestination: CampusWebDestination?
    @State private var showingClassroomURLAlert = false
    @State private var tempClassroomURL = ""
    @State private var classroomURLs: [String: String] = [:]
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
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        
        let periods: [Period] = [
            .init(number: 1, start: "09:00", end: "10:30"),
            .init(number: 2, start: "10:40", end: "12:10"),
            .init(number: 3, start: "13:00", end: "14:30"),
            .init(number: 4, start: "14:40", end: "16:10"),
            .init(number: 5, start: "16:20", end: "17:50"),
            .init(number: 6, start: "18:00", end: "19:30")
        ]
        
        var results: [DayEvent] = []
        
        // 通常授業
        let regularEvents = viewModel.courses
            .filter { course in
                guard !course.isScheduleNote else { return false }
                if let courseDate = course.dateString {
                    return courseDate == dateString
                } else {
                    return course.weekday == weekday
                }
            }
            .map { course in
                let p = course.period.split(separator: ",").compactMap { Int($0) }.first ?? Int(course.period) ?? 1
                let classroomKey = weekdayIndex >= 0 ? "\(weekdayIndex)_\(p)_\(course.title)" : nil

                if let start = course.startTime, let end = course.endTime {
                    return DayEvent(
                        title: course.title,
                        startTime: start,
                        endTime: end,
                        location: course.room,
                        status: course.status,
                        classroomKey: classroomKey
                    )
                }

                let start = periods[min(max(0, p-1), periods.count-1)].start
                let end = periods[min(max(0, p-1), periods.count-1)].end
                return DayEvent(
                    title: course.title,
                    startTime: start,
                    endTime: end,
                    location: course.room,
                    status: course.status,
                    classroomKey: classroomKey
                )
            }
        results.append(contentsOf: regularEvents)
        
        // 集中講義（日程が入力されているもの）
        let intensiveEvents = viewModel.intensiveCourses
            .filter { $0.dates.contains(dateString) && !$0.dates.isEmpty }
            .map { course in
                DayEvent(
                    title: course.title,
                    startTime: course.startTime ?? "09:00",
                    endTime: course.endTime ?? "17:00",
                    location: course.location,
                    status: "集中",
                    classroomKey: nil,
                    isIntensive: true
                )
            }
        results.append(contentsOf: intensiveEvents)
        
        return results
    }

    private func scheduleNotes(for date: Date) -> [Course] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return viewModel.courses.filter { course in
            course.isScheduleNote && course.dateString == dateString
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
            viewModel.loadCachedData()
        }
        .sheet(item: $webDestination) { destination in
            CampusWebSheet(destination: destination, presentedDestination: $webDestination)
        }
        .alert("クラスルームURLを設定", isPresented: $showingClassroomURLAlert) {
            TextField("URLを入力", text: $tempClassroomURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("キャンセル", role: .cancel) {}
            Button("保存") {
                if let event = selectedActionEvent {
                    setClassroomURL(for: event, url: tempClassroomURL)
                }
            }
            Button("クリア", role: .destructive) {
                if let event = selectedActionEvent {
                    setClassroomURL(for: event, url: nil)
                }
            }
        } message: {
            Text("Google Classroom・Zoom等のURLを入力してください. ClassroomのURLはアプリではなくブラウザから取得できます。")
        }
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func openSyllabusSearch(for event: DayEvent) {
        UIPasteboard.general.string = event.title
        guard let url = URL(string: "https://cs.kunitachi.ac.jp/campusweb/campussquare.do?_flowId=SBW3701300-flow&link=menu-link-mf-164899") else { return }
        webDestination = CampusWebDestination(url: url, title: "シラバス参照", autoSearchText: event.title)
    }

    private func classroomURL(for event: DayEvent) -> String? {
        if classroomURLs.isEmpty {
            classroomURLs = PortalCacheStore.shared.loadClassroomURLs()
        }
        if let key = event.classroomKey, let url = classroomURLs[key] {
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
        }
        PortalCacheStore.shared.saveClassroomURLs(classroomURLs)
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

    private var weekOffsetRange: ClosedRange<Int> {
        let baseWeek = today.startOfWeek(calendar: calendar)
        let earliestDate = viewModel.earliestCachedDate() ?? calendar.date(byAdding: .day, value: -365, to: today) ?? today
        let earliestWeek = earliestDate.startOfWeek(calendar: calendar)
        let minDayDelta = calendar.dateComponents([.day], from: baseWeek, to: earliestWeek).day ?? -365
        let minWeekOffset = min(-52, minDayDelta / 7)
        return minWeekOffset...52
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingCalendar.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(yearLabel(selectedDate))
                            Text(monthDayLabel(selectedDate))
                        }
                        .font(.system(size: 17))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

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
        let lowerBound = viewModel.earliestCachedDate() ?? Calendar.current.date(byAdding: .day, value: -365, to: today)!
        // UIDatePickerのinlineスタイル（サイズ変動なし）
        return FixedHeightDatePicker(
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
            range: lowerBound...Calendar.current.date(byAdding: .day, value: 365, to: today)!
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
            ForEach(Array(weekOffsetRange), id: \.self) { offset in
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
        let notes = scheduleNotes(for: date)
        let slots = Array(startHour...endHour)
        let timeLabelWidth: CGFloat = 64
        let timeLabelHeight: CGFloat = 28
        let sidePadding: CGFloat = 8
        let totalHeight = CGFloat(slots.count) * hourHeight

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                if !notes.isEmpty {
                    ScheduleNotesBanner(notes: notes)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }

                GeometryReader { geo in
                    let cardMaxWidth = geo.size.width - (sidePadding * 2) - timeLabelWidth
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
                            transitionDirection: transitionDirection,
                            onShowSyllabus: { event in
                                openSyllabusSearch(for: event)
                            },
                            onShowClassroom: { event in
                                if let url = classroomURL(for: event) {
                                    openURL(url)
                                }
                            },
                            onEditClassroom: { event in
                                selectedActionEvent = event
                                tempClassroomURL = classroomURL(for: event) ?? ""
                                showingClassroomURLAlert = true
                            },
                            onScheduleAdjust: { _ in
                                onToggle()
                            },
                            classroomURL: { event in
                                classroomURL(for: event)
                            }
                        )
                        .id(date)

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
                            .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: totalHeight)
                .padding(.horizontal, sidePadding)
            }
        }
        .background(AppTheme.pageBackground)
        .refreshable {
            await PortalDataCoordinator.shared.refreshScheduleForOneYear(showUpdateBanner: true)
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

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日"
        return f
    }()

    private var currentTimeLabel: String {
        Self.timeFormatter.string(from: currentTime)
    }

    private func yearLabel(_ date: Date) -> String {
        Self.yearFormatter.string(from: date)
    }

    private func monthDayLabel(_ date: Date) -> String {
        Self.monthDayFormatter.string(from: date)
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

private struct ScheduleNotesBanner: View {
    let notes: [Course]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(notes) { note in
                HStack(alignment: .top, spacing: 8) {
                    Text(note.scheduleNoteCategory ?? "予定")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(categoryColor(for: note)))

                    Text(note.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func categoryColor(for note: Course) -> Color {
        switch note.scheduleNoteCategory {
        case "休日":
            return .orange
        case "特別期間":
            return AppTheme.accent
        default:
            return AppTheme.textMuted
        }
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
    let onShowSyllabus: (DayEvent) -> Void
    let onShowClassroom: (DayEvent) -> Void
    let onEditClassroom: (DayEvent) -> Void
    let onScheduleAdjust: (DayEvent) -> Void
    let classroomURL: (DayEvent) -> String?

    @State private var selectedMenuEventID: String?

    var body: some View {
        let grouped = groupOverlappingEvents(events)
        
        ZStack {
            ForEach(Array(grouped.enumerated()), id: \.offset) { groupIndex, group in
                ForEach(Array(group.enumerated()), id: \.element.id) { index, event in
                    EventCardView(
                        event: event,
                        width: cardMaxWidth,
                        xOffset: timeLabelWidth + CGFloat(index) * 6,
                        opacity: index == 0 ? 1.0 : 0.85,
                        hourHeight: hourHeight,
                        startHour: startHour,
                        selectedMenuEventID: $selectedMenuEventID,
                        onShowSyllabus: onShowSyllabus,
                        onShowClassroom: onShowClassroom,
                        onEditClassroom: onEditClassroom,
                        onScheduleAdjust: onScheduleAdjust,
                        classroomURL: classroomURL(event)
                    )
                }
            }
        }
        .id(date)
        .transition(.move(edge: .trailing))
        .animation(.easeInOut(duration: 0.25), value: date)
    }
    
    private func groupOverlappingEvents(_ events: [DayEvent]) -> [[DayEvent]] {
        var groups: [[DayEvent]] = []
        var currentGroup: [DayEvent] = []
        
        for event in events.sorted(by: { $0.startMinutes < $1.startMinutes }) {
            if let last = currentGroup.last {
                if event.startMinutes < last.endMinutes {
                    currentGroup.append(event)
                } else {
                    groups.append(currentGroup)
                    currentGroup = [event]
                }
            } else {
                currentGroup.append(event)
            }
        }
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        return groups
    }
}

// MARK: - 個別イベントカード
private struct EventCardView: View {
    let event: DayEvent
    let width: CGFloat
    let xOffset: CGFloat
    let opacity: Double
    let hourHeight: CGFloat
    let startHour: Int
    
    @Binding var selectedMenuEventID: String?
    let onShowSyllabus: (DayEvent) -> Void
    let onShowClassroom: (DayEvent) -> Void
    let onEditClassroom: (DayEvent) -> Void
    let onScheduleAdjust: (DayEvent) -> Void
    let classroomURL: String?
    
    private var isMenuOpen: Bool {
        selectedMenuEventID == event.id
    }
    
    var body: some View {
        let layout = event.layout(hourHeight: hourHeight, startHour: startHour)
        let isCancelled = event.status == "休講"
        let isSupplementary = event.status == "補講"
        let isIntensive = event.isIntensive
        let statusColor = isCancelled ? Color.red : (isSupplementary ? Color.blue : (isIntensive ? Color.orange : AppTheme.accent))
        let cardBg = isCancelled ? Color.red.opacity(0.1) : (isSupplementary ? Color.blue.opacity(0.1) : (isIntensive ? Color.orange.opacity(0.1) : Color.white.opacity(0.7)))
        let cardBorder = isCancelled ? Color.red.opacity(0.5) : (isSupplementary ? Color.blue.opacity(0.5) : (isIntensive ? Color.orange.opacity(0.5) : AppTheme.blueCardBorder))
        let isCompact = layout.height < 48

        return Group {
            if isCompact {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isCancelled ? .red : AppTheme.textPrimary)
                        .lineLimit(1)

                    Text("\(event.startTime)-\(event.endTime)")
                        .font(.system(size: 11))
                        .foregroundStyle(isSupplementary ? .blue : (isCancelled ? .red.opacity(0.8) : AppTheme.textBlue))
                        .lineLimit(1)

                    if !event.location.isEmpty {
                        Text(event.location)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if !event.status.isEmpty {
                        Text(event.status)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(statusColor)
                            .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top) {
                        Text(event.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isCancelled ? .red : AppTheme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        if !event.status.isEmpty {
                            Text(event.status)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(statusColor)
                                .cornerRadius(4)
                        }
                    }

                    Text("\(event.startTime) - \(event.endTime)")
                        .font(.system(size: 12))
                        .foregroundStyle(isSupplementary ? .blue : (isCancelled ? .red.opacity(0.8) : AppTheme.textBlue))

                    if !event.location.isEmpty {
                        Text(event.location)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textMuted)
                            .lineLimit(1)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: width, height: layout.height, alignment: .topLeading)
        .clipped()
        .opacity(opacity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorder, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .contentShape(Rectangle())
        .offset(x: xOffset, y: layout.top + 16)
        .onTapGesture {
            selectedMenuEventID = event.id
        }
        .popover(isPresented: Binding(
            get: { isMenuOpen },
            set: { if !$0 { selectedMenuEventID = nil } }
        ), attachmentAnchor: .rect(.rect(
            CGRect(x: xOffset, y: layout.top + 16, width: width, height: layout.height)
        )), arrowEdge: .bottom) {
            popoverMenu
                .presentationCompactAdaptation(.popover)
        }
    }
    
    @ViewBuilder
    private var popoverMenu: some View {
        VStack(spacing: 0) {
            if classroomURL != nil {
                Button { selectedMenuEventID = nil; onShowClassroom(event) } label: {
                    Label("クラスルームを表示", systemImage: "video")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                }
                Divider()
            }
            Button { selectedMenuEventID = nil; onEditClassroom(event) } label: {
                Label("クラスルームを設定", systemImage: "link.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
            }
            Divider()
            Button { selectedMenuEventID = nil; onShowSyllabus(event) } label: {
                Label("シラバスを表示", systemImage: "book")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
            }
            if event.isIntensive {
                Divider()
                Button { selectedMenuEventID = nil; onScheduleAdjust(event) } label: {
                    Label("日程を調整", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 220)
    }
}

private struct OverlappingEventsSheet: View {
    let events: [DayEvent]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(event.startTime) - \(event.endTime)")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textBlue)
                    if !event.location.isEmpty {
                        Text(event.location)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("重複イベント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}
