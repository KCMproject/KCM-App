import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel
    @AppStorage(AppSettings.passwordAutofillEnabled) private var autofillEnabled = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KCM Portal")
                        .font(.largeTitle.bold())
                    Text("ポータルの掲示板と時間割を見やすく確認するためのアプリ")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    TextField("学籍番号", text: $viewModel.studentID)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding()
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    SecureField("パスワード", text: $viewModel.password)
                        .textFieldStyle(.plain)
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding()
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        viewModel.login()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("ログイン")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isLoading)
                }

                Toggle(isOn: $autofillEnabled) {
                    Text("ログイン情報を自動入力する")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textMuted)
                }
                .tint(AppTheme.accent)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                }

                Spacer()
            }
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea())
        }
        .overlay {
            if viewModel.isLoading {
                Color.white.opacity(0.7)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("ロード中…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    LoginView(viewModel: LoginViewModel.shared)
}
