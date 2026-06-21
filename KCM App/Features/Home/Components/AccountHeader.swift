import SwiftUI

struct AccountHeader: View {
    let userName: String
    let userReading: String

    var body: some View {
        let initial = String(userName.isEmpty ? "?" : userName.prefix(1))

        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color(red: 0.29, green: 0.36, blue: 0.45))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text(initial)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(userReading.isEmpty ? userName : userReading)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if !userName.isEmpty {
                        Text(userName)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }
}
