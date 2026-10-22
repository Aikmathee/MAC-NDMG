import SwiftUI

extension RootView {
    func authenticationSheet(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 30, weight: .light)).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 7) {
                Text(server.name).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(server.address).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Form {
                TextField("Username", text: $store.username).textContentType(.username)
                SecureField("Password", text: $store.password).textContentType(.password)
                    .onSubmit { Task { await store.submitAuthentication() } }
                Toggle("Remember account", isOn: $store.rememberAccount)
                    .help("Save this app’s account in Keychain after signing in.")
            }.formStyle(.grouped).frame(height: 180)
            if let message = store.authError {
                Text(message).font(.system(size: 12)).foregroundStyle(store.finderSignInPending ? Color.secondary : Color.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { store.cancelAuthentication() }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use Finder") { Task { await store.useFinderSignIn() } }
                    .buttonStyle(FramedButtonStyle()).help("Use macOS sign-in and saved Finder accounts.")
                if store.authSubmitting { ProgressView().controlSize(.small) }
                Button(store.authSubmitting ? "Signing in…" : "Sign in") { Task { await store.submitAuthentication() } }
                    .buttonStyle(PillStyle(primary: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 420).background(Color(nsColor: .windowBackgroundColor)).disabled(store.authSubmitting)
            .interactiveDismissDisabled(store.authSubmitting)
    }
    var addSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "plus.circle.fill").font(.system(size: 32)).foregroundStyle(.blue)
            Text("Add server").font(.system(size: 24, weight: .bold, design: .rounded))
            Form {
                TextField("Address", text: $store.newAddress, prompt: Text("Hostname or smb://server/Share"))
                TextField("Name", text: $store.newName, prompt: Text("Optional"))
            }.formStyle(.grouped).frame(height: 130)
            HStack {
                ConnectionHelpButton()
                Button("Cancel") { store.showingAdd = false }.keyboardShortcut(.cancelAction).buttonStyle(PillStyle())
                Spacer()
                Button("Add") { Task { await store.add() } }.keyboardShortcut(.defaultAction).buttonStyle(PillStyle(primary: true))
                    .disabled(!store.validNewAddress)
            }
        }.padding(32).frame(width: 460).background(Color(nsColor: .windowBackgroundColor))
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
            .padding(28).frame(width: 480, height: 340).background(Color(nsColor: .windowBackgroundColor))
    }
}
