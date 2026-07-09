import SwiftUI

struct PasswordManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.passwordAutofillEnabled) private var isAutofillEnabled = false

    @State private var studentID: String
    @State private var password: String
    let onSave: (String, String) -> Void

    init(initialCredentials: SavedCredentials?, isAutofillEnabled: Bool, onSave: @escaping (String, String) -> Void) {
        _studentID = State(initialValue: initialCredentials?.studentID ?? "")
        _password = State(initialValue: initialCredentials?.password ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("保存したログイン情報は端末内に保存されます。自動入力をオンにすると、アプリ起動時にこの情報でログインを試します。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textMuted)

                VStack(spacing: 16) {
                    TextField("学籍番号", text: $studentID)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding()
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    SecureField("パスワード", text: $password)
                        .textFieldStyle(.plain)
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding()
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                HStack {
                    Text("自動入力")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Toggle("", isOn: $isAutofillEnabled)
                        .labelsHidden()
                        .tint(AppTheme.accent)
                }
                .padding(.vertical, 8)

                Spacer()
            }
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("パスワード管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let trimmedID = studentID.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedID.isEmpty, !trimmedPassword.isEmpty else { return }
                        onSave(trimmedID, trimmedPassword)
                        dismiss()
                    }
                    .disabled(
                        studentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}
