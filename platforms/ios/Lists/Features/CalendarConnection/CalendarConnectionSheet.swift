import SwiftUI
import EventKit

struct CalendarConnectionSheet: View {
    let store: ItemStore
    var initialListID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var service = CalendarConnections.shared
    @State private var showingSetup = false
    @State private var editing: CalendarConnections.Connection?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Bring Apple Calendar events into your lists. Copies stay editable here; your changes never change Apple Calendar.")
                        .foregroundStyle(.secondary)
                }
                if !service.authorized {
                    Section {
                        Button("Allow Calendar Access", systemImage: "calendar.badge.plus") {
                            Task { await service.requestAccess() }
                        }.accessibilityIdentifier("calendar.connection.authorize")
                        if EKEventStore.authorizationStatus(for: .event) == .denied {
                            Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                                .accessibilityIdentifier("calendar.connection.settings")
                        }
                    } footer: { Text("Lists reads only the calendars you choose after permission is granted.") }
                }
                if !service.connections.isEmpty {
                    Section("Your calendars") {
                        ForEach(service.connections) { connection in
                            connectionRow(connection)
                        }
                    }
                }
                if service.authorized {
                    if service.calendars.isEmpty {
                        Text("No calendars found. Add an account in Apple Calendar, then reopen this screen.").foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Connect a Calendar", systemImage: "calendar.badge.plus") { showingSetup = true }
                            .accessibilityIdentifier("calendar.connection.add")
                        if service.connections.contains(where: \.enabled) {
                            Button("Refresh Now", systemImage: "arrow.clockwise") { Task { await service.refresh(store: store) } }
                                .accessibilityIdentifier("calendar.connection.refresh")
                        }
                    }
                }
                if service.busy { ProgressView("Updating calendars…") }
                if let error = service.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("calendar.connection.error") }
            }
            .disabled(service.busy)
            .navigationTitle("Apple Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly)
                    .accessibilityIdentifier("calendar.connection.done")
            } }
            .sheet(isPresented: $showingSetup) { CalendarConnectionSetupView(store: store, service: service, initialListID: initialListID) }
            .sheet(item: $editing) { CalendarConnectionSetupView(store: store, service: service, initialListID: initialListID, connection: $0) }
            .task { if service.authorized { await service.requestAccess() } }
        }
        .tint(ListsTokens.accent)
    }

    private func connectionRow(_ connection: CalendarConnections.Connection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar").foregroundStyle(ListsTokens.accent)
                Text(connection.name).font(.headline)
                Spacer()
                Text(connection.enabled ? "Connected" : "Paused").font(.caption).foregroundStyle(.secondary)
            }
            Text(store.lists.first { $0.id == connection.listID }?.name ?? "Choose another list")
                .font(.subheadline).foregroundStyle(.secondary)
            if let error = service.connectionErrors[connection.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if let last = connection.lastRefresh {
                Text("Updated \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            let conflicts = store.items.filter { $0.deletedAt == nil && $0.calendarImport?.connectionID == connection.id && $0.calendarImport?.conflicts.isEmpty == false }
            if !conflicts.isEmpty {
                NavigationLink("Review \(conflicts.count) source changes") {
                    List(conflicts) { item in
                        NavigationLink(item.title) { CalendarSourceView(store: store, itemID: item.id) }
                            .accessibilityIdentifier("calendar.connection.item.\(item.id.uuidString.lowercased())")
                    }.navigationTitle("Source Changes")
                }.accessibilityIdentifier("calendar.connection.conflicts.\(connection.id.uuidString.lowercased())")
            }
            Button("Manage") { editing = connection }
                .accessibilityIdentifier("calendar.connection.edit.\(connection.id)")
        }.padding(.vertical, 6)
    }
}

private struct CalendarConnectionSetupView: View {
    let store: ItemStore
    let service: CalendarConnections
    let connection: CalendarConnections.Connection?
    @Environment(\.dismiss) private var dismiss
    @State private var calendarID: String
    @State private var listID: String
    @State private var start: Date
    @State private var end: Date
    @State private var advanced = false
    @State private var showNewList = false
    @State private var confirmDisconnect = false
    @State private var previousListIDs: Set<String> = []

    init(store: ItemStore, service: CalendarConnections, initialListID: String?, connection: CalendarConnections.Connection? = nil) {
        self.store = store; self.service = service; self.connection = connection
        _calendarID = State(initialValue: connection?.calendarID ?? "")
        _listID = State(initialValue: connection?.listID ?? initialListID ?? ItemList.inboxId)
        _start = State(initialValue: connection?.start ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)!)
        _end = State(initialValue: connection?.end ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)!)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    Picker("Apple Calendar", selection: $calendarID) {
                        Text("Choose Calendar").tag("")
                        ForEach(service.calendars) { calendar in
                            Text("\(calendar.title) · \(calendar.account)").tag(calendar.id)
                        }
                        if let connection, !service.calendars.contains(where: { $0.id == connection.calendarID }) {
                            Text(connection.name + " · Unavailable").tag(connection.calendarID)
                        }
                    }.disabled(connection != nil).accessibilityIdentifier("calendar.connection.source")
                }
                Section("Into") {
                    Picker("List", selection: $listID) {
                        ForEach(store.lists.filter { $0.deletedAt == nil }) { Text($0.name).tag($0.id) }
                    }.accessibilityIdentifier("calendar.connection.destination")
                    Button("New List", systemImage: "folder.badge.plus") {
                        previousListIDs = Set(store.lists.map(\.id)); showNewList = true
                    }.accessibilityIdentifier("calendar.connection.newlist")
                }
                Section {
                    DisclosureGroup("Advanced", isExpanded: $advanced) {
                        DatePicker("From", selection: $start, displayedComponents: .date).accessibilityIdentifier("calendar.connection.start")
                        DatePicker("Until", selection: $end, displayedComponents: .date).accessibilityIdentifier("calendar.connection.end")
                        Text("Up to three years. Extend this range when needed. Changing the list affects new copies only.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("calendar.connection.advanced")
                } footer: {
                    Text("Updates arrive while Lists is open. Your edits are protected. Calendar alarms, attachments and invitations remain in Apple Calendar.")
                }
                Section {
                    Button(connection == nil ? "Connect Calendar" : "Save Connection") {
                        guard let calendar = service.calendars.first(where: { $0.id == calendarID }) else { return }
                        Task {
                            await service.connect(calendar: calendar, listID: listID, start: start, end: end, store: store)
                            if service.error == nil { dismiss() }
                        }
                    }
                    .disabled(service.busy || !service.calendars.contains(where: { $0.id == calendarID })
                        || !store.lists.contains(where: { $0.id == listID && $0.deletedAt == nil }) || start >= end)
                    .accessibilityIdentifier("calendar.connection.connect")
                    if let connection, connection.enabled {
                        Button("Disconnect", role: .destructive) { confirmDisconnect = true }
                            .accessibilityIdentifier("calendar.connection.disconnect.\(connection.id)")
                    }
                }
                if let error = service.error { Text(error).foregroundStyle(.red) }
                if service.busy { ProgressView("Connecting…") }
            }
            .navigationTitle(connection == nil ? "Connect Calendar" : "Manage Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                    .accessibilityIdentifier("calendar.connection.cancel")
            } }
            .interactiveDismissDisabled(service.busy)
            .confirmationDialog("Disconnect this calendar? Your copies stay in Lists.", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect — Keep Items", role: .destructive) {
                    if let connection { service.disconnect(connection.id); if service.error == nil { dismiss() } }
                }.accessibilityIdentifier("calendar.connection.disconnect.confirm")
            }
            .sheet(isPresented: $showNewList, onDismiss: {
                if let created = store.lists.first(where: { !previousListIDs.contains($0.id) && $0.deletedAt == nil }) { listID = created.id }
            }) { ListEditSheet(store: store) }
        }
    }
}

struct CalendarSourceView: View {
    let store: ItemStore
    let itemID: UUID
    @State private var error: String?
    var body: some View {
        Form {
            if let item = store.item(itemID), let origin = item.calendarImport {
                Section("Apple Calendar · \(origin.calendarName)") {
                    Text(item.title).font(.headline)
                    Text(origin.detached ? "Updates stopped" : "Incoming connection")
                    Text("Last checked \(origin.checkedAt.formatted())")
                    if origin.sourceUnavailable { Text("No longer returned by the source. It may have been removed or moved outside the import range. Your item has been kept.") }
                }
                Section("Latest Source Values") {
                    LabeledContent("Title", value: origin.baseline.title)
                    Text(origin.baseline.body)
                    Text("\(origin.baseline.start.formatted()) – \(origin.baseline.end.formatted())")
                }
                ForEach(origin.conflicts, id: \.self) { field in
                    Section("\(field.label) Changed in Both Apps") {
                        Button("Keep Mine") { resolve(field, source: false, item: item) }
                            .accessibilityIdentifier("calendar.source.keep.\(field.rawValue)")
                        Button("Use Apple Calendar’s \(field.label)") { resolve(field, source: true, item: item) }
                            .accessibilityIdentifier("calendar.source.accept.\(field.rawValue)")
                    }
                }
                if !origin.detached {
                    Button("Stop Receiving Updates") {
                        var updated = item; updated.calendarImport?.detached = true
                        updated.calendarImport?.conflicts = []
                        save(updated)
                    }.accessibilityIdentifier("calendar.source.detach")
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Calendar Source")
    }
    private func resolve(_ field: CalendarImport.Field, source: Bool, item: Item) {
        save(CalendarImport.resolve(field, useSource: source, item: item))
    }
    private func save(_ item: Item) {
        Task { do { try await store.update(item) } catch { self.error = error.localizedDescription } }
    }
}
