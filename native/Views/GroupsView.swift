import SwiftUI

extension RootView {
    var groupsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Groups & saved drives").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("⌘-click to combine groups or drives · Control-click for actions")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let message = store.libraryError { Text(message).font(.system(size: 12)).foregroundStyle(.orange) }
            List(selection: $store.librarySelection) {
                Text("Groups").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.top, 4).padding(.bottom, 2)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
                    .accessibilityAddTraits(.isHeader)
                if store.groups.isEmpty {
                    Label("Create a group to connect your drives together.", systemImage: "square.stack.3d.up")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        .modifier(ContentCard(radius: 18))
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                ForEach(store.groups) { group in
                    groupCard(group)
                            .modifier(CardSelection(selected: store.librarySelection.contains("group:" + group.id), radius: 24))
                            .tag("group:" + group.id).listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                Text("Saved drives").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.top, 12).padding(.bottom, 2)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
                    .accessibilityAddTraits(.isHeader)
                ForEach(store.rememberedDrives.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { drive in
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive").font(.system(size: 22)).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(drive.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(drive.serverName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if store.isConnected(drive) {
                            Label("Connected", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green)
                        } else {
                            Button("Connect") { Task { await store.connectSaved([drive], label: drive.name) } }
                                .buttonStyle(PillStyle()).disabled(store.working)
                        }
                    }.padding(16).modifier(ContentCard(radius: 18))
                        .modifier(CardSelection(selected: store.librarySelection.contains("drive:" + drive.id), radius: 18))
                        .tag("drive:" + drive.id)
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
            }.listStyle(.inset(alternatesRowBackgrounds: false)).scrollContentBackground(.hidden).disabled(store.working)
                .contextMenu(forSelectionType: String.self) { ids in libraryContext(ids) }
            if !store.librarySelection.isEmpty {
                HStack {
                    Text("\(store.savedForLibrary(store.librarySelection).count) selected").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save as group…") { store.groupFromSaved(store.savedForLibrary(store.librarySelection)) }.buttonStyle(PillStyle())
                    Button("Eject") { Task { await store.ejectVolumes(store.volumesForSaved(store.savedForLibrary(store.librarySelection))) } }
                        .buttonStyle(PillStyle()).disabled(store.working || store.volumesForSaved(store.savedForLibrary(store.librarySelection)).isEmpty)
                    Button("Connect") { Task { await store.connectSaved(store.savedForLibrary(store.librarySelection), label: "Selection") } }
                        .buttonStyle(PillStyle(primary: true)).disabled(store.working)
                }.modifier(SelectionActionBar())
            }
        }.padding(24)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.librarySelection.isEmpty)
    }
    func groupCard(_ group: DriveGroup) -> some View {
        let drives = store.drivesForGroup(group)
        let connected = drives.filter { store.isConnected($0) }.count
        return VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 23)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    Text("\(connected) of \(drives.count) connected").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Connect group") { Task { await store.connectSaved(store.drivesForGroup(group), label: group.name) } }
                    Button("Eject group") { Task { await store.ejectVolumes(store.volumesForSaved(store.drivesForGroup(group))) } }
                        .disabled(store.volumesForSaved(store.drivesForGroup(group)).isEmpty)
                    Divider()
                    Button("Edit group") { store.editGroup(group) }
                    Button("Delete group", role: .destructive) { store.pendingDeleteGroup = group }
                } label: { Image(systemName: "ellipsis").padding(8) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(store.working)
                    .accessibilityLabel("Options for \(group.name)")
            }
            Text(drives.prefix(4).map { "\($0.name) · \($0.serverName)" }.joined(separator: "\n") + (drives.count > 4 ? "\n+\(drives.count - 4) more" : ""))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            HStack {
                if connected > 0 {
                    Button("Eject group") { Task { await store.ejectVolumes(store.volumesForSaved(drives)) } }
                        .buttonStyle(PillStyle()).disabled(store.working)
                }
                Spacer()
                Button {
                    Task { await store.connectSaved(drives, label: group.name) }
                } label: {
                    Label(connected == drives.count ? "Connected" : "Connect group", systemImage: connected == drives.count ? "checkmark" : "link")
                }.buttonStyle(PillStyle(primary: connected != drives.count))
                    .disabled(drives.isEmpty || connected == drives.count || store.working || store.loading)
            }
        }.padding(22).modifier(ContentCard())
    }

    var groupEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(store.editingGroupID == nil ? "New group" : "Edit group")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "square.stack.3d.up").font(.system(size: 25)).foregroundStyle(.blue)
            }
            field("Group name") { TextField("Editing room", text: $store.newGroupName) }
            HStack {
                Text("Choose drives").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Select connected") {
                    store.newGroupDriveIDs = Set(store.rememberedDrives.filter { store.isConnected($0) }.map(\.id))
                }.buttonStyle(.borderless)
                Button("Clear") { store.newGroupDriveIDs = [] }.buttonStyle(.borderless)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.rememberedDrives) { drive in
                        Toggle(isOn: Binding(get: { store.newGroupDriveIDs.contains(drive.id) }, set: { selected in
                            if selected { store.newGroupDriveIDs.insert(drive.id) } else { store.newGroupDriveIDs.remove(drive.id) }
                        })) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(drive.name).font(.system(size: 13, weight: .medium))
                                    Text(drive.serverName).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.isConnected(drive) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12)) }
                            }
                        }.toggleStyle(.checkbox).padding(.vertical, 4)
                    }
                }.padding(4)
            }.frame(maxHeight: .infinity)
            if let message = store.groupEditorError { Text(message).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { store.showingGroupEditor = false }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
                Text("\(store.newGroupDriveIDs.count) selected").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(store.savingGroup ? "Saving…" : "Save group") { Task { await store.saveGroup() } }
                    .buttonStyle(PillStyle(primary: true)).keyboardShortcut(.defaultAction)
                    .disabled(store.newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.newGroupName.count > 80 || store.newGroupDriveIDs.isEmpty || store.savingGroup)
            }
        }.padding(28).frame(width: 490, height: 560).disabled(store.savingGroup)
    }

}
