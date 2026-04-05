import SwiftUI

struct ClassDetailView: View {
    let course: Course

    var body: some View {
        List {
            Section("授業情報") {
                LabeledContent("授業名", value: course.title)
                LabeledContent("担当教員", value: course.instructor)
                LabeledContent("教室", value: course.room)
                LabeledContent("状態", value: course.status)
            }

            Section("次回授業") {
                Text(course.nextClassInfo)
            }

            Section("講義資料") {
                ForEach(course.materials, id: \.self) { material in
                    Text(material)
                }
            }

            Section("課題") {
                ForEach(course.assignments, id: \.self) { assignment in
                    Text(assignment)
                }
            }
        }
        .navigationTitle("授業詳細")
    }
}
