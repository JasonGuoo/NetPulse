import SwiftUI

struct AppSettingsMenu: View {
    @AppStorage(AppPreferences.menuBarEnabledKey) private var menuBarEnabled = true
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Menu {
            Toggle(isOn: menuBarBinding) {
                Label(L10n.t("settings.menubar.show"), systemImage: "menubar.rectangle")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(menuBarEnabled ? Theme.cyan : Theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.04)))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.t("settings.title"))
        .environment(\.colorScheme, .dark)
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { menuBarEnabled },
            set: { enabled in
                menuBarEnabled = enabled
                AppPreferences.notifyMenuBarVisibilityChanged()
            }
        )
    }
}

struct NetPulseSettingsView: View {
    @AppStorage(AppPreferences.menuBarEnabledKey) private var menuBarEnabled = true
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(nsImage: AppDelegate.renderIcon(size: 36))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("settings.title"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    Text("NetPulse")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textFaint)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(menuBarEnabled ? Theme.cyan : Theme.textFaint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.04)))

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t("settings.menubar"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text(L10n.t("settings.menubar.detail"))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: menuBarBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.strongHairline, lineWidth: 0.8)
            )
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.bgGradient)
        .preferredColorScheme(.dark)
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { menuBarEnabled },
            set: { enabled in
                menuBarEnabled = enabled
                AppPreferences.notifyMenuBarVisibilityChanged()
            }
        )
    }
}
