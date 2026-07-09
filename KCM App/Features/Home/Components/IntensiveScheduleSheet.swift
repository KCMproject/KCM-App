import SwiftUI

struct IntensiveScheduleSheet: View {
    let courseID: UUID?
    let courseTitle: String
    let semester: TimetableSemester
    @Binding var intensiveCourses: [IntensiveCourseCard]
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddSheet = false

    private var existingCourse: IntensiveCourseCard? {
        if let id = courseID, let course = intensiveCourses.first(where: { $0.id == id }) {
            return course
        }
        if !courseTitle.isEmpty, let course = intensiveCourses.first(where: { $0.title == courseTitle }) {
            return course
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("登録済み日程")) {
                    if existingCourse?.dateRanges.isEmpty ?? true {
                        Text("まだ日程が追加されていません")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textMuted)
                    } else {
                        ForEach(existingCourse?.dateRanges ?? []) { range in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(range.formatted)
                                        .font(.system(size: 14, weight: .semibold))
                                    if let start = range.startTime, let end = range.endTime {
                                        Text("\(start) 〜 \(end)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.textBlue)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    deleteRange(range)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
            .id(existingCourse?.dateRanges.count ?? -1)
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
        .sheet(isPresented: $showingAddSheet) {
            IntensiveScheduleAddSheet(
                courseID: courseID,
                courseTitle: courseTitle,
                semester: semester,
                intensiveCourses: $intensiveCourses
            )
            .presentationDetents([.height(480)])
        }
    }

    private func courseIndex(matchingID id: UUID?, title: String, in courses: [IntensiveCourseCard]) -> Int? {
        courses.firstIndex { course in
            if let id, course.id == id { return true }
            if !title.isEmpty, course.title == title { return true }
            return false
        }
    }

    private func deleteRange(_ range: DateRange) {
        guard let index = courseIndex(matchingID: courseID, title: courseTitle, in: intensiveCourses) else { return }
        var updated = intensiveCourses[index]
        updated.dateRanges.removeAll { $0.id == range.id }
        var newCourses = intensiveCourses
        newCourses[index] = updated
        intensiveCourses = newCourses
        PortalCacheStore.shared.saveIntensiveCourses(intensiveCourses, for: semester)
    }
}

struct IntensiveScheduleAddSheet: View {
    let courseID: UUID?
    let courseTitle: String
    let semester: TimetableSemester
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

    private func courseIndex(matchingID id: UUID?, title: String, in courses: [IntensiveCourseCard]) -> Int? {
        courses.firstIndex { course in
            if let id, course.id == id { return true }
            if !title.isEmpty, course.title == title { return true }
            return false
        }
    }

    private func addSchedule() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let trimmedStart = startTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnd = endTimeText.trimmingCharacters(in: .whitespacesAndNewlines)

        let newRange = DateRange(
            startDate: formatter.string(from: startDate),
            endDate: formatter.string(from: endDate),
            startTime: trimmedStart.isEmpty ? nil : trimmedStart,
            endTime: trimmedEnd.isEmpty ? nil : trimmedEnd
        )

        guard let index = courseIndex(matchingID: courseID, title: courseTitle, in: intensiveCourses) else {
            dismiss()
            return
        }
        var updated = intensiveCourses[index]
        updated.dateRanges.append(newRange)
        var newCourses = intensiveCourses
        newCourses[index] = updated
        intensiveCourses = newCourses
        PortalCacheStore.shared.saveIntensiveCourses(intensiveCourses, for: semester)

        dismiss()
    }
}
