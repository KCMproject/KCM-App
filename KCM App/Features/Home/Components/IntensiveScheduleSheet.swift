import SwiftUI

struct IntensiveScheduleSheet: View {
    let courseID: UUID?
    let courseTitle: String
    let semester: TimetableSemester
    @ObservedObject private var viewModel = TimetableViewModel.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddSheet = false
    @State private var dateRanges: [DateRange] = []

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("登録済み日程")) {
                    if dateRanges.isEmpty {
                        Text("まだ日程が追加されていません")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textMuted)
                    } else {
                        ForEach(dateRanges) { range in
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
            .navigationTitle("日程を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $showingAddSheet) {
                IntensiveScheduleAddSheet(
                    onSave: { newRange in
                        addRange(newRange)
                    }
                )
            }
        }
        .onAppear {
            loadDateRanges()
        }
        .onChange(of: viewModel.intensiveCourses) {
            loadDateRanges()
        }
    }

    private func loadDateRanges() {
        if let id = courseID, let course = viewModel.intensiveCourses.first(where: { $0.id == id }) {
            dateRanges = course.dateRanges
        } else if !courseTitle.isEmpty, let course = viewModel.intensiveCourses.first(where: { $0.title == courseTitle }) {
            dateRanges = course.dateRanges
        }
    }

    private func addRange(_ range: DateRange) {
        dateRanges.append(range)
        viewModel.updateIntensiveCourseDateRanges(
            courseID: courseID,
            courseTitle: courseTitle,
            dateRanges: dateRanges,
            for: semester
        )
    }

    private func deleteRange(_ range: DateRange) {
        dateRanges.removeAll { $0.id == range.id }
        viewModel.updateIntensiveCourseDateRanges(
            courseID: courseID,
            courseTitle: courseTitle,
            dateRanges: dateRanges,
            for: semester
        )
    }
}

struct IntensiveScheduleAddSheet: View {
    let onSave: (DateRange) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var startTimeText = "09:00"
    @State private var endTimeText = "17:00"

    var body: some View {
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
                    saveSchedule()
                }
            }
        }
    }

    private func saveSchedule() {
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

        onSave(newRange)
        dismiss()
    }
}
