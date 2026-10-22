import SwiftUI
import AppKit

struct ConnectionHelpButton: View {
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: { Image(systemName: "questionmark.circle") }
            .buttonStyle(FramedButtonStyle()).accessibilityLabel("Connection help")
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Server address").font(.headline)
                    Text("Use a hostname such as nas.local, an SMB share URL, or a WebDAV URL.")
                    Text("SMB: smb://nas/Media\nWebDAV: https://cloud.example.com/dav/")
                    Text("For remote servers, connect your VPN first and use its DNS name. FTP/SFTP need another client.")
                }.font(.system(size: 12)).padding(20).frame(width: 330)
            }
    }
}

extension RootView {
    var appHelp: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                helpSection("Connect", "Choose a server, load its drives, then connect the ones you need. Servers already connected in Finder also appear here.")
                helpSection("Saved accounts", "The app first tries an existing macOS SMB session. If sign-in is needed, choose Use Finder to let macOS use its saved account, or enter an account in the app. macOS may ask again when the server address or account changes.")
                helpSection("Select drives", "Command-click adds or removes an item. Shift-click selects a range. Command-A selects all. Control-click opens actions for the selection.")
                helpSection("Groups", "Save a selection as a group, then connect or eject the group when needed. Deleting a group leaves its drives connected. If a drive moved to another server, choose Find on a saved drive or Find in LAN after an incomplete connection. Confirm the disk before updating its location; matching names alone do not prove identity.")
                helpSection("Servers & VPN", "Discovery uses Bonjour, the local SMB subnet, and current Finder connections. For other networks, connect your VPN and add a hostname or share URL. Prefer hostnames to changing IP addresses.")
                helpSection("Eject", "Eject uses normal macOS unmounting. If a drive is busy, close its files and the apps shown in the message, then retry. The app never forces an unmount or closes apps. macOS may hide processes belonging to another user or the system.")
                Link("User guide", destination: URL(string: "https://github.com/Aikmathee/MAC-NDMG/blob/main/docs/USER_GUIDE.md")!)
            }.padding(.vertical, 12)
        }.modifier(NativeScrollEdges())
            .modifier(NativeSafeAreaBar(edge: .top) {
                HStack {
                    Text("Help").font(.title2.bold())
                    Spacer()
                    Button("Done") { store.showingHelp = false }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
                }.padding(.bottom, 16)
            })
            .padding(28).frame(width: 540, height: 500)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    func helpSection(_ title: String, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(explanation).font(.system(size: 13)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    func ejectProblemSheet(_ problem: EjectProblem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(problem.failures) { failure in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(failure.name, systemImage: "externaldrive").font(.headline)
                        Text(failure.summary).font(.system(size: 12))
                        if failure.processes.isEmpty {
                            Text("No app identified. Check the connection and close any open files.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            Text("Apps using this drive").font(.system(size: 12)).foregroundStyle(.secondary)
                            ForEach(failure.processes) { process in
                                HStack {
                                    Label(process.displayName, systemImage: "app")
                                    Spacer()
                                    Text("PID \(String(process.pid))").foregroundStyle(.secondary)
                                }.font(.system(size: 12))
                            }
                        }
                        if failure.limited {
                            Text("macOS may hide some processes.").font(.caption).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Details") {
                            Text(failure.message).font(.system(size: 12)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                        }.font(.system(size: 12))
                    }.padding(16).modifier(ContentCard(radius: 18))
                }
            }.padding(.vertical, 8)
        }.modifier(NativeScrollEdges())
            .modifier(NativeSafeAreaBar(edge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(problem.failures.count == 1 ? "Couldn’t eject drive" : "Couldn’t eject drives", systemImage: "exclamationmark.triangle")
                        .font(.title2.bold())
                    Text("Close open files, then retry.").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
            })
            .modifier(NativeSafeAreaBar(edge: .bottom) {
                HStack {
                    Button("Activity Monitor") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }.buttonStyle(FramedButtonStyle())
                    Spacer()
                    Button("Done") { store.ejectProblem = nil }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
                    Button("Retry") {
                        store.pendingEjectIDs = Set(problem.failures.map(\.id))
                        store.ejectProblem = nil
                    }.buttonStyle(PillStyle(primary: true))
                }.padding(.top, 16)
            })
            .padding(28).frame(width: 540, height: 460)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
