import SwiftUI

extension RootView {
    func authenticationSheet(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 30, weight: .light)).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 7) {
                Text("Connect to \(server.name)").font(.system(size: 22, weight: .bold, design: .rounded))
                Text(server.address).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Form {
                TextField("Username", text: $store.username).textContentType(.username)
                SecureField("Password", text: $store.password).textContentType(.password)
                    .onSubmit { Task { await store.submitAuthentication() } }
                Toggle("Remember this server", isOn: $store.rememberAccount)
            }.formStyle(.grouped).frame(height: 180)
            Text(store.rememberAccount ? "Saved in Keychain after a successful sign-in." : "Used only for this app session.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = store.authError {
                Text(message).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { store.cancelAuthentication() }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                if store.authSubmitting { ProgressView().controlSize(.small) }
                Button(store.authSubmitting ? "Connecting…" : "Continue") { Task { await store.submitAuthentication() } }
                    .buttonStyle(PillStyle(primary: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 420).disabled(store.authSubmitting)
            .interactiveDismissDisabled(store.authSubmitting)
    }
    var addSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "plus.circle.fill").font(.system(size: 32)).foregroundStyle(.blue)
            Text("Add a server").font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Add a LAN server, VPN destination or WebDAV drive.").foregroundStyle(.secondary)
            Form {
                TextField("Address", text: $store.newAddress, prompt: Text("nas.example.ts.net or smb://server/Share"))
                TextField("Name", text: $store.newName, prompt: Text("Optional"))
            }.formStyle(.grouped).frame(height: 130)
            HStack {
                Button("Cancel") { store.showingAdd = false }.keyboardShortcut(.cancelAction).buttonStyle(PillStyle())
                Spacer()
                Button("Add") { Task { await store.add() } }.keyboardShortcut(.defaultAction).buttonStyle(PillStyle(primary: true))
                    .disabled(!store.validNewAddress)
            }
            Text("SMB: smb://nas/Share\nWebDAV: https://cloud.example.com/dav/\nConnect Tailscale or your VPN first. Remote servers do not appear in LAN scans.")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("WebDAV uses the macOS sign-in window. FTP and SFTP need a separate client.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(32).frame(width: 460)
    }

    var activitySheet: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.history.isEmpty { Text("No recent activity.").foregroundStyle(.secondary) }
                    ForEach(Array(store.history.enumerated()), id: \.offset) { _, message in
                        Text(message).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.textSelection(.enabled)
            }
            .modifier(NativeScrollEdges())
            .modifier(NativeSafeAreaBar(edge: .top) {
            HStack {
                Text("Activity").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { store.showingActivity = false }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
            }
                .padding(.bottom, 18)
            })
            .padding(28).frame(width: 480, height: 340)
    }
}
