import SwiftUI
import UIKit

struct WeeklyTimetableCloneView: View {
    @ObservedObject private var viewModel = TimetableViewModel.shared
    @StateObject private var classroomURLManager = ClassroomURLManager()
    @State private var webDestination: CampusWebDestination?
    @State private var showingScheduleSheet = false
    @State private var selectedCourseID: UUID?
    @State private var selectedCourseTitle = ""

    let onToggle: () -> Void

    private let periods = Period.standardPeriods

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

    private func requestClassroomURLEdit(for key: String) {
        classroomURLManager.startEditing(key: key)
    }

    private func openSyllabusSearch(for title: String) {
        SyllabusSearchOpener.openSearch(for: title) { self.webDestination = $0 }
    }

    private var hasVisibleSchedule: Bool {
        weeklyScheduleHasContent(viewModel.weeklySchedule)
    }

    private var isShowingClassroomAlert: Binding<Bool> {
        Binding(
            get: { classroomURLManager.isEditing },
            set: { isPresented in
                classroomURLManager.isEditing = isPresented
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            semesterHeader
            weekdayHeader
            ZStack {
                timetableGrid
                loadingOverlay
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
        }
        .classroomURLEditAlert(manager: classroomURLManager)
        .sheet(item: $webDestination) { destination in
            CampusWebSheet(destination: destination, presentedDestination: $webDestination)
        }
        .sheet(isPresented: $showingScheduleSheet) {
            IntensiveScheduleSheet(
                courseID: selectedCourseID,
                courseTitle: selectedCourseTitle,
                semester: viewModel.selectedSemester,
                intensiveCourses: $viewModel.intensiveCourses
            )
            .presentationDetents([.height(480)])
        }
        .onAppear {
            viewModel.loadCachedData()
            classroomURLManager.load()
        }
    }

    private var semesterHeader: some View {
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
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
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
    }

    private var timetableGrid: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(periods.enumerated()), id: \.offset) { rowIndex, period in
                    HStack(spacing: 0) {
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

                        ForEach(0..<dayLabels.count, id: \.self) { columnIndex in
                            let isToday = columnIndex == todayIndex
                            let item = viewModel.weeklySchedule[rowIndex][columnIndex]
                            let cellKey = timetableCellKey(for: item, period: period.number, weekdayIndex: columnIndex)
                            TimetableCell(
                                item: item,
                                isToday: isToday,
                                period: period.number,
                                weekdayIndex: columnIndex,
                                classroomURL: classroomURLManager.urls[cellKey],
                                onOpenClassroomURL: classroomURLManager.open,
                                onOpenSyllabusSearch: openSyllabusSearch,
                                onEditClassroomURL: {
                                    requestClassroomURLEdit(for: cellKey)
                                },
                                onAddSchedule: {
                                    if let title = item.title,
                                       let course = viewModel.intensiveCourses.first(where: { $0.title == title }) {
                                        selectedCourseID = course.id
                                        selectedCourseTitle = course.title
                                        showingScheduleSheet = true
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                intensiveCoursesSection
            }
        }
        .refreshable {
            await PortalDataCoordinator.shared.refreshWeeklyTimetable(showUpdateBanner: true)
        }
    }

    private var intensiveCoursesSection: some View {
        Group {
            if !viewModel.intensiveCourses.isEmpty {
                VStack(spacing: 12) {
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
                        let courseKey = "\(course.title)_\(course.period)"
                        IntensiveCourseRow(
                            course: course,
                            classroomURL: classroomURLManager.urls[courseKey],
                            onEdit: {
                                selectedCourseID = course.id
                                selectedCourseTitle = course.title
                                showingScheduleSheet = true
                            },
                            onOpenSyllabusSearch: openSyllabusSearch,
                            onEditClassroomURL: {
                                requestClassroomURLEdit(for: courseKey)
                            },
                            onOpenClassroomURL: { url in
                                classroomURLManager.open(url)
                            }
                        )
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var loadingOverlay: some View {
        Group {
            if viewModel.isLoading && !hasVisibleSchedule {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.5))
            } else if let error = viewModel.errorMessage, !error.isEmpty, !hasVisibleSchedule {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.textSoft)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.5))
            }
        }
    }
}


