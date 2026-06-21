import SwiftUI

struct SettingsSection: View {
    let title: String
    let rows: [SettingRow]
    let customContent: AnyView?

    init(title: String, rows: [SettingRow], customContent: AnyView? = nil) {
        self.title = title
        self.rows = rows
        self.customContent = customContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSoft)
                .padding(.horizontal, 4)

            if let customContent {
                customContent
            }

            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        switch row.kind {
                        case .toggle(let binding):
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.grayPill)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        Image(systemName: row.icon)
                                            .foregroundStyle(row.color)
                                    }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.title)
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    if let subtitle = row.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.textMuted)
                                    }
                                }

                                Spacer()

                                Toggle("", isOn: binding)
                                    .labelsHidden()
                                    .tint(AppTheme.accent)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        case .link(let action):
                            let rowView = HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.grayPill)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        Image(systemName: row.icon)
                                            .foregroundStyle(row.color)
                                    }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.title)
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    if let subtitle = row.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.textMuted)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.gray.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)

                            Button(action: action) {
                                rowView.contentShape(Rectangle())
                            }
                            .buttonStyle(AccountRowButtonStyle())
                        }

                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 1)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.gray.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
            }
        }
        .background(Color.clear)
    }
}

private struct AccountRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gray.opacity(0.12) : Color.clear)
    }
}
