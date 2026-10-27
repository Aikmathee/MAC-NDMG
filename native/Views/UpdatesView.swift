import SwiftUI

extension RootView {
    var updateBanner: some View {
        Group {
            if updates.showBanner, let update = updates.available {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
                    Text("\(update.title) is available.").font(.callout)
                    Spacer()
                    Button("Downloads") { openURL(update.releaseURL) }.buttonStyle(FramedButtonStyle())
                    Button("Later") { updates.showBanner = false }.buttonStyle(FramedButtonStyle())
                }.padding(12).background(.regularMaterial)
            }
        }
    }
    var updatesSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Updates").font(.title2.bold())
                Spacer()
                Button("Done") { showingUpdates = false }.buttonStyle(FramedButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            Text("MacNDMG \(AppReleaseInfo.displayVersion)")
                .foregroundStyle(.secondary)
            Picker("Check for updates", selection: $updates.intervalDays) {
                Text("Every day").tag(1)
                Text("Every 2 days").tag(2)
                Text("Off").tag(0)
            }.pickerStyle(.menu)
            Text("Checks while MacNDMG is open. Downloads open on GitHub; you install the update yourself.")
                .font(.callout).foregroundStyle(.secondary)
            if !updates.status.isEmpty { Text(updates.status).font(.callout) }
            HStack {
                Button(updates.checking ? "Checking…" : "Check now") {
                    Task { await updates.check(manual: true) }
                }.buttonStyle(PillStyle()).disabled(updates.checking)
                Spacer()
                Button("Downloads") {
                    openURL(updates.available?.releaseURL ?? URL(string: "https://github.com/Aikmathee/MAC-NDMG/releases/latest")!)
                }.buttonStyle(PillStyle(primary: true))
            }
        }.padding(24).frame(width: 480)
    }
}
