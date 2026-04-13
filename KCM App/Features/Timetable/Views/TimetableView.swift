import SwiftUI

struct TimetableView: View {
    let courses: [Course]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(courses), id: \Course.id) { course in
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
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("時間割")
        .padding(.horizontal, 16)
        .background(AppTheme.background)
    }
}

#Preview {
    NavigationStack {
        TimetableView(courses: MockPortalService().fetchCourses())
    }
}
