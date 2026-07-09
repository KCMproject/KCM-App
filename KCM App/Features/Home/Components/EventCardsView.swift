import SwiftUI

// MARK: - イベントカード（スライドアニメーション対応）
struct EventCardsView: View {
    let date: Date
    let events: [DayEvent]
    let cardMaxWidth: CGFloat
    let hourHeight: CGFloat
    let startHour: Int
    let timeLabelWidth: CGFloat
    let transitionDirection: TransitionDirection
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
                    .zIndex(event.isIntensive ? 0 : 1)
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
        var groupMaxEnd: Int = 0

        for event in events.sorted(by: { $0.startMinutes < $1.startMinutes }) {
            if !currentGroup.isEmpty {
                if event.startMinutes < groupMaxEnd {
                    currentGroup.append(event)
                    groupMaxEnd = max(groupMaxEnd, event.endMinutes)
                } else {
                    groups.append(currentGroup)
                    currentGroup = [event]
                    groupMaxEnd = event.endMinutes
                }
            } else {
                currentGroup.append(event)
                groupMaxEnd = event.endMinutes
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
                menuButton(title: "クラスルームを表示", systemImage: "video") {
                    selectedMenuEventID = nil; onShowClassroom(event)
                }
                Divider()
            }
            menuButton(title: "クラスルームを設定", systemImage: "link.badge.plus") {
                selectedMenuEventID = nil; onEditClassroom(event)
            }
            Divider()
            menuButton(title: "シラバスを表示", systemImage: "book") {
                selectedMenuEventID = nil; onShowSyllabus(event)
            }
            if event.isIntensive {
                Divider()
                menuButton(title: "日程を調整", systemImage: "calendar.badge.plus") {
                    selectedMenuEventID = nil; onScheduleAdjust(event)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 220)
    }

    private func menuButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
        }
    }
}
