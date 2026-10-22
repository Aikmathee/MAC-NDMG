import SwiftUI

extension RootView {
    var driveRecoverySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Drives not connected").font(.title2.bold())
                Spacer()
                Button("Done") { store.showingRecovery = false }.buttonStyle(FramedButtonStyle())
            }
            Text(store.recoveryMessage).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.unavailableDrives) { drive in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(drive.name).fontWeight(.semibold)
                                Text("Saved on \(drive.serverName)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if drive.connectionProtocol != "webdav" {
                                Button("Find in LAN") { Task { await store.findDrive(drive) } }
                                    .buttonStyle(FramedButtonStyle()).disabled(store.recoverySearching)
                            }
                        }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if store.recoverySearching { ProgressView() }
                    if let drive = store.recoveryDrive {
                        ForEach(store.recoveryCandidates) { server in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(drive.share) · \(server.name)")
                                    Text(server.address).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Use this location") { Task { await store.useLocation(server) } }
                                    .buttonStyle(FramedButtonStyle()).disabled(store.recoverySearching)
                            }.padding(12)
                        }
                    }
                }
            }
            Text("A share name cannot prove disk identity. Search checks accessible SMB shares without sending saved passwords to other servers.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 620, height: 460)
    }
}
