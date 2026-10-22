import SwiftUI

extension RootView {
    var home: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network drives").font(.system(size: 30, weight: .bold, design: .rounded))

                }.frame(maxWidth: .infinity, alignment: .leading)
                if !store.mountedVolumes.isEmpty { connectedPreview }
                overviewGroups
                Section {
                    if store.visible.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: store.scanning ? "wifi" : "network").font(.system(size: 28)).foregroundStyle(.secondary)
                            Text(store.scanning ? "Looking for servers…" : store.search.isEmpty ? "No servers found" : "No matching servers").font(.headline)
                            Text(store.scanning ? "This usually takes a few seconds." : "Connect to your network, or add a server address.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(30).modifier(ContentCard())
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                            ForEach(store.visible) { server in
                                Button { store.serverClicked(server) } label: { serverCard(server) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(server.name), \(server.address)")
                                    .contextMenu { serverContext(store.selectedServerIDs.contains(server.id) ? store.selectedServerIDs : [server.id]) }
                            }
                        }
                    }
                } header: { overviewServersHeader }
            }.padding(34)
        }.modifier(NativeScrollEdges())
    }

    var overviewServersHeader: some View {
        HStack {
            Text("Servers").font(.system(size: 17, weight: .semibold))
            Spacer()
            if store.scanning { ProgressView().controlSize(.small) }
            Button { store.showingAdd = true } label: {
                Label("Add server", systemImage: "plus")
            }.buttonStyle(FramedButtonStyle())
        }
        .padding(.vertical, 14)
    }
}
