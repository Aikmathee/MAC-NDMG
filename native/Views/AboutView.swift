import SwiftUI

enum AppReleaseInfo {
    static var displayVersion: String {
        Bundle.main.infoDictionary?["NDMGDisplayVersion"] as? String ?? buildVersion
    }
    static var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
    static let contact = URL(string: "https://www.instagram.com/aik_mathee/")!
    static let bugReport = URL(string: "https://github.com/Aikmathee/MAC-NDMG/issues/new?template=bug_report.md")!
    static let coffee = URL(string: "https://buymeacoffee.com/aik_mathee")!
}

extension RootView {
    var supportMenu: some View {
        Menu {
            Button("About MacNDMG") { showingAbout = true }
            Button("Updates") { showingUpdates = true }
            Divider()
            Link("Contact me", destination: AppReleaseInfo.contact)
            Link("Report a bug", destination: AppReleaseInfo.bugReport)
            Link("Buy me a coffee", destination: AppReleaseInfo.coffee)
        } label: {
            Label("About & support", systemImage: "ellipsis.circle")
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
        }.menuStyle(.borderlessButton).accessibilityLabel("About and support")
    }

    var aboutSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("MacNDMG").font(.title.bold())
                Spacer()
                Button("Done") { showingAbout = false }.buttonStyle(FramedButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            Text(AppReleaseInfo.displayVersion).font(.title2)
            Text("A preview release for connecting network drives.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Button("Contact me") { openURL(AppReleaseInfo.contact) }.buttonStyle(FramedButtonStyle())
                Button("Report a bug") { openURL(AppReleaseInfo.bugReport) }.buttonStyle(FramedButtonStyle())
                Button("Buy me a coffee") { openURL(AppReleaseInfo.coffee) }.buttonStyle(FramedButtonStyle())
            }
            Text("Build \(AppReleaseInfo.buildVersion)").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 420)
    }
}
