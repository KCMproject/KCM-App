import SwiftUI

struct ScheduleNotesBanner: View {
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
