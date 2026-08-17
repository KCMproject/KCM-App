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
    @StateObject private var classroomURLManager = ClassroomURLManager()
    @AppStorage(AppSettings.tapToSwitchDayEnabled) private var tapToSwitchDayEnabled = true
    let onToggle: () -> Void

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

        var results: [DayEvent] = []
        results.append(contentsOf: makeRegularEvents(for: date, dateString: dateString, weekday: weekday, weekdayIndex: weekdayIndex))
        results.append(contentsOf: makeIntensiveEvents(for: date, dateString: dateString))
        return results
    }

    private func makeRegularEvents(for date: Date, dateString: String, weekday: String, weekdayIndex: Int) -> [DayEvent] {
        let periods = Period.standardPeriods
        return viewModel.courses
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
    }

    private func makeIntensiveEvents(for date: Date, dateString: String) -> [DayEvent] {
        viewModel.intensiveCourses
            .filter { $0.allDates.contains(dateString) && !$0.dateRanges.isEmpty }
            .map { course in
                let matchingRange = course.dateRanges.first { $0.dates.contains(dateString) }
                return DayEvent(
                    title: course.title,
                    startTime: matchingRange?.startTime ?? course.startTime ?? "09:00",
                    endTime: matchingRange?.endTime ?? course.endTime ?? "17:00",
                    location: course.location,
                    status: "集中",
                    classroomKey: nil,
                    isIntensive: true
                )
            }
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

                    if let error = viewModel.errorMessage, !error.isEmpty, events(for: selectedDate).isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundStyle(AppTheme.textSoft)
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.7))
                    }
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
            classroomURLManager.load()
        }
        .sheet(item: $webDestination) { destination in
            CampusWebSheet(destination: destination, presentedDestination: $webDestination)
        }
        .classroomURLEditAlert(manager: classroomURLManager)
    }

    private func openSyllabusSearch(for event: DayEvent) {
        SyllabusSearchOpener.openSearch(for: event.title) { self.webDestination = $0 }
    }

    private func classroomURL(for event: DayEvent) -> String? {
        classroomURLManager.url(for: event.classroomKey ?? event.id)
    }

    private func startEditingClassroomURL(for event: DayEvent) {
        selectedActionEvent = event
        classroomURLManager.startEditing(key: event.classroomKey ?? event.id, currentURL: classroomURL(for: event))
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
        let lowerBound = viewModel.earliestCachedDate() ?? Calendar.current.date(byAdding: .day, value: -365, to: today) ?? today
        let upperBound = Calendar.current.date(byAdding: .day, value: 365, to: today) ?? today
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
            range: lowerBound...upperBound
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
                weekDayButton(date: date, selected: selected, isToday: isToday)
            }
        }
    }

    private func weekDayButton(date: Date, selected: Bool, isToday: Bool) -> some View {
        let dayIndex = Calendar.current.component(.weekday, from: date) - 1
        let textColor: Color = dayIndex == 0 ? .red.opacity(0.7) : dayIndex == 6 ? AppTheme.accent.opacity(0.8) : AppTheme.textMuted

        return Button {
            setDisplayedDate(date)
        } label: {
            VStack(spacing: 4) {
                Text(WeekdayLabels.full[dayIndex])
                    .font(.system(size: 12))
                    .foregroundStyle(textColor)
                Text("\(Calendar.current.component(.day, from: date))")
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
                        timelineGridLines(slots: slots)
                        timelineTimeLabels(slots: slots, timeLabelWidth: timeLabelWidth, timeLabelHeight: timeLabelHeight)
                        timelineTapZones(sideZoneWidth: sideZoneWidth, centerDeadZoneWidth: centerDeadZoneWidth)

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
                                    classroomURLManager.open(url)
                                }
                            },
                            onEditClassroom: { event in
                                startEditingClassroomURL(for: event)
                            },
                            onScheduleAdjust: { _ in
                                onToggle()
                            },
                            classroomURL: { event in
                                classroomURL(for: event)
                            }
                        )
                        .id(date)

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
            .padding(.bottom, 96)
        }
        .background(AppTheme.pageBackground)
        .onScrollGeometryChange(for: ScrollInfo.self) { geometry in
            let maxOffset = max(0, geometry.contentSize.height - geometry.visibleRect.height)
            return ScrollInfo(offset: geometry.contentOffset.y, maxOffset: maxOffset)
        } action: { old, new in
            TabBarScrollState.shared.handleScroll(oldOffset: old.offset, newOffset: new.offset, maxOffset: new.maxOffset)
        }
        .refreshable {
            await PortalDataCoordinator.shared.refreshScheduleForOneYear(showUpdateBanner: true)
        }
    }

    private func timelineGridLines(slots: [Int]) -> some View {
        ForEach(slots, id: \.self) { hour in
            let y = CGFloat(hour - startHour) * hourHeight + 16
            Capsule()
                .fill(AppTheme.lightBlueBorder.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 1.5)
                .offset(y: y)
        }
    }

    private func timelineTimeLabels(slots: [Int], timeLabelWidth: CGFloat, timeLabelHeight: CGFloat) -> some View {
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
    }

    private func timelineTapZones(sideZoneWidth: CGFloat, centerDeadZoneWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: sideZoneWidth)
                .contentShape(Rectangle())
                .onTapGesture { shiftDate(by: -1) }

            Color.clear
                .frame(width: centerDeadZoneWidth)

            Color.clear
                .frame(width: sideZoneWidth)
                .contentShape(Rectangle())
                .onTapGesture { shiftDate(by: 1) }
        }
        .zIndex(-1)
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


