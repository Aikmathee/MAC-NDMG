import SwiftUI

extension RootView {
    var groupsPage: some View {
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
        }.listStyle(.inset(alternatesRowBackgrounds: false)).scrollContentBackground(.hidden)
            .modifier(NativeScrollEdges()).disabled(store.working)
            .contextMenu(forSelectionType: String.self) { ids in libraryContext(ids) }
            .modifier(NativeSafeAreaBar(edge: .top) { libraryHeader })
            .modifier(NativeSafeAreaBar(edge: .bottom) { libraryActions })
            .padding(24)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.librarySelection.isEmpty)
    }
    var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Groups & saved drives").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("⌘-click to select multiple · Control-click for actions")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let message = store.libraryError { Text(message).font(.system(size: 12)).foregroundStyle(.orange) }
        }.padding(.bottom, 16)
    }

    @ViewBuilder var libraryActions: some View {
        if !store.librarySelection.isEmpty {
            HStack {
                Text("\(store.savedForLibrary(store.librarySelection).count) selected").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Save as group…") { store.groupFromSaved(store.savedForLibrary(store.librarySelection)) }.buttonStyle(PillStyle())
                Button("Eject") { Task { await store.ejectVolumes(store.volumesForSaved(store.savedForLibrary(store.librarySelection))) } }
                    .buttonStyle(PillStyle()).disabled(store.working || store.volumesForSaved(store.savedForLibrary(store.librarySelection)).isEmpty)
                Button("Connect") { Task { await store.connectSaved(store.savedForLibrary(store.librarySelection), label: "Selection") } }
                    .buttonStyle(PillStyle(primary: true)).disabled(store.working)
            }.modifier(SelectionActionBar()).padding(.top, 12)
        }
    }

    func groupCard(_ group: DriveGroup) -> some View {
        let drives = store.drivesForGroup(group)
        let connected = drives.filter { store.isConnected($0) }.count
        let serverCount = Set(drives.map { $0.address.lowercased() }).count
        let expanded = expandedGroupIDs.contains(group.id)
        let complete = !drives.isEmpty && connected == drives.count
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 22, weight: .medium)).foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    HStack(spacing: 6) {
                        Circle().fill(complete ? Color.green : connected > 0 ? Color.blue : Color.secondary)
                            .frame(width: 5, height: 5).accessibilityHidden(true)
                        Text("\(connected) of \(drives.count) connected · \(serverCount) \(serverCount == 1 ? "server" : "servers")")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("Connect group") { Task { await store.connectSaved(drives, label: group.name) } }
                        .disabled(drives.isEmpty || complete)
                    Button("Eject group") { Task { await store.ejectVolumes(store.volumesForSaved(drives)) } }
                        .disabled(connected == 0)
                    Divider()
                    Button("Edit group…") { store.editGroup(group) }
                    Button("Delete group", role: .destructive) { store.pendingDeleteGroup = group }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(store.working)
                    .accessibilityLabel("Options for \(group.name)")
            }
            HStack(spacing: 10) {
                Button {
                    if expanded { expandedGroupIDs.remove(group.id) }
                    else { expandedGroupIDs.insert(group.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold)).frame(width: 10)
                        Text("\(drives.count) \(drives.count == 1 ? "drive" : "drives")")
                            .font(.system(size: 12, weight: .medium))
                    }.foregroundStyle(.secondary).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(expanded ? "Hide" : "Show") drives in \(group.name)")
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                Spacer(minLength: 8)
                Button { Task { await store.ejectVolumes(store.volumesForSaved(drives)) } } label: {
                    Label("Eject", systemImage: "eject")
                }.buttonStyle(PillStyle()).disabled(connected == 0 || store.working || store.loading)
                    .accessibilityLabel("Eject group \(group.name)")
                Button { Task { await store.connectSaved(drives, label: group.name) } } label: {
                    Label(complete ? "Connected" : "Connect", systemImage: complete ? "checkmark" : "link")
                }.buttonStyle(PillStyle(primary: !complete))
                    .disabled(drives.isEmpty || complete || store.working || store.loading)
                    .accessibilityLabel(complete ? "All drives in \(group.name) are connected" : "Connect group \(group.name)")
            }
            if expanded {
                Divider().opacity(0.45)
                groupMembers(drives)
                    .transition(.opacity)
            }
        }.padding(20).modifier(ContentCard())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: expanded)
    }

    func groupMembers(_ drives: [SavedDrive]) -> some View {
        let members = Dictionary(grouping: drives, by: { $0.address.lowercased() })
        let addresses = members.keys.sorted { lhs, rhs in
            (members[lhs]?.first?.serverName ?? lhs).localizedStandardCompare(members[rhs]?.first?.serverName ?? rhs) == .orderedAscending
        }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(addresses, id: \.self) { address in
                let items = (members[address] ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                VStack(alignment: .leading, spacing: 5) {
                    Label(items.first?.serverName ?? address, systemImage: "desktopcomputer")
                        .font(.system(size: 12, weight: .medium))
                    Text(items.map(\.name).joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.vertical, 2)
    }

    var groupEditor: some View {
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
            .modifier(NativeScrollEdges())
            .modifier(NativeSafeAreaBar(edge: .top) { groupEditorHeader })
            .modifier(NativeSafeAreaBar(edge: .bottom) { groupEditorActions })
            .padding(28).frame(width: 490, height: 560).disabled(store.savingGroup)
    }

    var groupEditorHeader: some View {
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
                }.buttonStyle(FramedButtonStyle())
                Button("Clear") { store.newGroupDriveIDs = [] }.buttonStyle(FramedButtonStyle())
            }
        }.padding(.bottom, 16)
    }

    var groupEditorActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = store.groupEditorError { Text(message).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { store.showingGroupEditor = false }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
                Text("\(store.newGroupDriveIDs.count) selected").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(store.savingGroup ? "Saving…" : "Save group") { Task { await store.saveGroup() } }
                    .buttonStyle(PillStyle(primary: true)).keyboardShortcut(.defaultAction)
                    .disabled(store.newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.newGroupName.count > 80 || store.newGroupDriveIDs.isEmpty || store.savingGroup)
            }
        }.padding(.top, 16)
    }

}
