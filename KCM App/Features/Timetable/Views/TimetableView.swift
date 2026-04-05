import SwiftUI

struct TimetableView: View {
    let courses: [Course]
    private var courseIndices: [Int] { courses.enumerated().map(\.offset) }

    var body: some View {
        List {
            ForEach(courseIndices, id: \.self) { index in
                let course = courses[index]
                NavigationLink {
                    ClassDetailView(course: course)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(course.weekday) \(course.period)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                            Spacer()
                            Text(course.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(course.title)
                            .font(.headline)

                        Text(course.room)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("時間割")
        .listStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        TimetableView(courses: MockPortalService().fetchCourses())
    }
}
