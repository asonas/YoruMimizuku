import SwiftUI

struct UpdateSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var updateController: UpdateController

    private var versionDisplay: String {
        UpdateBadgeState.versionDisplay(
            shortVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("アップデート")
                    .font(.app(.headline))
                    .foregroundStyle(theme.primaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("現在のバージョン")
                        .font(.app(.caption))
                        .foregroundStyle(theme.secondaryText)
                    Text(versionDisplay)
                        .font(.app(.callout, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("配信チャンネル")
                        .font(.app(.caption))
                        .foregroundStyle(theme.secondaryText)
                    Picker("配信チャンネル", selection: $updateController.channel) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.title).tag(channel)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(updateController.channel.explanation)
                        .font(.app(.caption2))
                        .foregroundStyle(theme.secondaryText)
                    if updateController.channel == .development {
                        Text("開発版からリリース版へ戻しても自動で downgrade はされません。次のリリース版の build number が現在の開発版より大きい場合に更新されます。すぐ戻す場合は手動で再インストールしてください。")
                            .font(.app(.caption2))
                            .foregroundStyle(theme.star)
                    }
                }

                Toggle("起動時に自動で確認", isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.automaticallyChecksForUpdates = $0 }
                ))

                Button {
                    updateController.checkForUpdates()
                } label: {
                    Label("今すぐ確認", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!updateController.canCheckForUpdates)

                if updateController.updateAvailable {
                    Label("利用可能なアップデートがあります。今すぐ確認からインストールできます。", systemImage: "arrow.down.circle.fill")
                        .font(.app(.callout))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
