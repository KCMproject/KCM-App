import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel

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

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("担当分担")
                        .font(.headline)
                    Text("ハシグチ: UI/デザインと共通コンポーネント")
                    Text("タナカ: ログイン、セッション管理、認証周り")
                    Text("トクダ: データ取得、パーサ、掲示板/時間割の連携")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea())
        }
    }
}

#Preview {
    LoginView(viewModel: LoginViewModel(portalClient: PortalClientFactory.makeLoginService()))
}
