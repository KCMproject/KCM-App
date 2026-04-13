import SwiftUI
import Combine

struct TodayTimelineView: View {
    @State private var currentTime = Date()
    @State private var selectedDate = Date()
    @State private var dateOffset = 0
    @State private var showingCalendar = false
    @State private var calendarMonth = Date()
    @AppStorage(AppSettings.tapToSwitchDayEnabled) private var tapToSwitchDayEnabled = true
    let onToggle: () -> Void

    private let calendar = Calendar(identifier: .gregorian)
    private let hourHeight: CGFloat = 74
    private let startHour = 9
    private let endHour = 22

    private let eventsByDay: [Int: [DayEvent]] = [
        2: [ // 月曜日
            .init(title: "線形代数学", startTime: "09:00", endTime: "10:30", location: "第1講義棟 A101"),
            .init(title: "英語コミュニケーション", startTime: "10:45", endTime: "12:15", location: "第2講義棟 B205"),
            .init(title: "プログラミング基礎", startTime: "13:00", endTime: "14:30", location: "情報処理センター PC-301"),
            .init(title: "物理学実験", startTime: "14:45", endTime: "16:15", location: "実験棟 E-102"),
            .init(title: "ゼミナール", startTime: "16:30", endTime: "18:00", location: "研究棟 R-405")
        ],
        3: [ // 火曜日
            .init(title: "物理学概論", startTime: "09:00", endTime: "10:30", location: "第2講義棟 B203"),
            .init(title: "情報理論", startTime: "10:45", endTime: "12:15", location: "情報処理センター PC-201"),
            .init(title: "微分積分学", startTime: "13:00", endTime: "14:30", location: "第1講義棟 A102"),
            .init(title: "文概論", startTime: "14:45", endTime: "16:15", location: "第2講義棟 C205")
        ],
        4: [ // 水曜日
            .init(title: "化学基礎", startTime: "10:45", endTime: "12:15", location: "実験棟 D104"),
            .init(title: "体育実技", startTime: "13:00", endTime: "14:30", location: "体育館"),
            .init(title: "統計学", startTime: "14:45", endTime: "16:15", location: "第1講義棟 A301")
        ],
        5: [ // 木曜日
            .init(title: "線形代数学", startTime: "09:00", endTime: "10:30", location: "第1講義棟 A101"),
            .init(title: "英語コミュニケーション", startTime: "10:45", endTime: "12:15", location: "第2講義棟 B205"),
            .init(title: "プログラミング基礎", startTime: "13:00", endTime: "14:30", location: "情報処理センター PC-301"),
            .init(title: "物理学実験", startTime: "14:45", endTime: "16:15", location: "実験棟 E-102"),
            .init(title: "ゼミナール", startTime: "16:30", endTime: "18:00", location: "研究棟 R-405")
        ],
        6: [ // 金曜日
            .init(title: "経済学入門", startTime: "09:00", endTime: "10:30", location: "第3講義棟 C301"),
            .init(title: "哲学概論", startTime: "10:45", endTime: "12:15", location: "第2講義棟 A203"),
            .init(title: "社会学", startTime: "14:45", endTime: "16:15", location: "第3講義棟 B301")
        ]
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                weekStrip(for: selectedDate)
                TabView(selection: $dateOffset) {
                    ForEach(-365...365, id: \.self) { offset in
                        let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
                        timeline(for: date)
                            .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: dateOffset)
                .onChange(of: dateOffset) { _, newOffset in
                    selectedDate = calendar.date(byAdding: .day, value: newOffset, to: today) ?? today
                }
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
    }

    @ViewBuilder
    private func dayPage(for date: Date) -> some View {
        VStack(spacing: 0) {
            weekStrip(for: date)
            timeline(for: date)
        }
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
                    selectedDate = Date()
                    dateOffset = 0
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
                    selectedDate = newDate
                    if let newOffset = calendar.dateComponents([.day], from: today, to: newDate).day {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            dateOffset = newOffset
                        }
                    }
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

    private func weekStrip(for targetDate: Date) -> some View {
        let today = Date()
        let weekStart = targetDate.startOfWeek(calendar: calendar)
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }

        return HStack(spacing: 0) {
            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                let selected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDate(date, inSameDayAs: today)
                let dayIndex = calendar.component(.weekday, from: date) - 1
                let textColor: Color = dayIndex == 0 ? .red.opacity(0.7) : dayIndex == 6 ? AppTheme.accent.opacity(0.8) : AppTheme.textMuted

                Button {
                    selectedDate = date
                    if let newOffset = calendar.dateComponents([.day], from: today, to: date).day {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            dateOffset = newOffset
                        }
                    }
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
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private func timeline(for date: Date) -> some View {
        let events = eventsByDay[calendar.component(.weekday, from: date)] ?? []
        let slots = Array(startHour...endHour)
        let timeLabelWidth: CGFloat = 64
        let sidePadding: CGFloat = 8
        let totalHeight = CGFloat(slots.count) * hourHeight

        return ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // 背景のグリッド線
                ForEach(slots, id: \.self) { hour in
                    let y = CGFloat(hour - startHour) * hourHeight
                    HStack(spacing: 0) {
                        Text("\(hour):00")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textMuted)
                            .frame(width: timeLabelWidth, alignment: .topLeading)
                            .padding(.top, 8)
                            .padding(.trailing, 12)

                        Rectangle()
                            .fill(hour % 3 == 0 ? AppTheme.textSoft.opacity(0.25) : AppTheme.lightBlueBorder.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                    }
                    .frame(height: hourHeight, alignment: .top)
                    .offset(y: y)
                }

                // イベントカード
                ForEach(events) { event in
                    let layout = event.layout(hourHeight: hourHeight, startHour: startHour)
                    let cardMaxWidth = UIScreen.main.bounds.width - timeLabelWidth - (sidePadding * 2) - 16
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
                    .frame(width: cardMaxWidth, height: max(layout.height, 50), alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.blueCardBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                    .offset(x: timeLabelWidth + sidePadding, y: layout.top)
                }

                // 現在時刻の線＋ラベル
                if let indicatorTop = currentIndicatorTop {
                    HStack(spacing: 0) {
                        Text(currentTimeLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.7)))

                        Rectangle()
                            .fill(Color.red.opacity(0.4))
                            .frame(height: 1)
                    }
                    .offset(x: timeLabelWidth + sidePadding, y: indicatorTop)
                }
            }
            .frame(height: totalHeight)
            .padding(.horizontal, sidePadding)
        }
        .background(AppTheme.pageBackground)
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
