import SwiftUI
import EventKit

struct CalendarConnectionSheet: View {
    let store: ItemStore
    var initialListID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var service = CalendarConnections.shared
    @State private var calendarID = ""
    @State private var listID = ""
    @State private var start = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var end = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
    @State private var showNewList = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Apple Calendar events become editable Lists items. Your changes stay in Lists and are never sent back to Apple Calendar.")
                    Text("Imports titles, notes, locations, links and dates. Calendar alarms, attachments and invitation responses stay in Apple Calendar.").font(.caption).foregroundStyle(.secondary)
                    Text("This device refreshes connections while Lists is open. Other-device sync is not included.")
                        .foregroundStyle(.secondary)
                }
                if !service.connections.isEmpty {
                    Section("Connections") {
                        ForEach(service.connections) { connection in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(connection.name).font(.headline)
                                Text("New items → \(store.lists.first { $0.id == connection.listID }?.name ?? "Unavailable list")")
                                Text(connection.enabled ? "Connected" : "Disconnected · items kept").foregroundStyle(.secondary)
                                if let last = connection.lastRefresh {
                                    Text("Updated \(last.formatted())").font(.caption).foregroundStyle(.secondary)
                                }
                                Text("\(connection.start.formatted(date: .abbreviated, time: .omitted)) – \(connection.end.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                Button("Edit Connection") {
                                    calendarID = connection.calendarID; listID = connection.listID
                                    start = connection.start; end = connection.end
                                    Task { await service.requestAccess() }
                                }.accessibilityIdentifier("calendar.connection.edit.\(connection.id)")
                                if connection.enabled {
                                    Button("Disconnect — Keep Items", role: .destructive) { service.disconnect(connection.id) }
                                        .accessibilityIdentifier("calendar.connection.disconnect.\(connection.id)")
                                }
                            }
                        }
                        Button("Refresh Now") { Task { await service.refresh(store: store) } }
                            .accessibilityIdentifier("calendar.connection.refresh")
                    }
                }
                Section("Connect Calendar") {
                    if service.calendars.isEmpty {
                        Button("Choose Apple Calendar") { Task { await service.requestAccess() } }
                            .accessibilityIdentifier("calendar.connection.authorize")
                    } else {
                        Picker("Apple Calendar", selection: $calendarID) {
                            Text("Choose Calendar").tag("")
                            ForEach(service.calendars, id: \.calendarIdentifier) { calendar in
                                Text("\(calendar.title) · \(calendar.source.title)").tag(calendar.calendarIdentifier)
                            }
                        }.accessibilityIdentifier("calendar.connection.source")
                        Picker("Destination List", selection: $listID) {
                            Text("Choose List").tag("")
                            ForEach(store.lists.filter { $0.deletedAt == nil }) { list in Text(list.name).tag(list.id) }
                        }.accessibilityIdentifier("calendar.connection.destination")
                        Button("New List") { showNewList = true }.accessibilityIdentifier("calendar.connection.newlist")
                        DatePicker("Import From", selection: $start, displayedComponents: .date)
                            .accessibilityIdentifier("calendar.connection.start")
                        DatePicker("Import Until", selection: $end, displayedComponents: .date)
                            .accessibilityIdentifier("calendar.connection.end")
                        Text("Up to three years. Repeating events import as individual occurrences. Extend the range here when needed. Changing the destination affects new imports only.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Connect and Import") {
                            guard let calendar = service.calendars.first(where: { $0.calendarIdentifier == calendarID }) else { return }
                            Task { await service.connect(calendar: calendar, listID: listID, start: start, end: end, store: store) }
                        }
                        .disabled(calendarID.isEmpty || listID.isEmpty || start >= end)
                        .accessibilityIdentifier("calendar.connection.connect")
                    }
                }
                if let error = service.error { Section { Text(error).foregroundStyle(.red) } }
                if service.busy { ProgressView("Updating calendars…") }
                let linked = store.items.filter { $0.deletedAt == nil && $0.calendarImport != nil && (initialListID == nil || $0.listId == initialListID) }
                if !linked.isEmpty {
                    Section("Imported Items") {
                        ForEach(linked) { item in
                            NavigationLink {
                                CalendarSourceView(store: store, itemID: item.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                    if item.calendarImport?.conflicts.isEmpty == false { Text("Source updated").font(.caption).foregroundStyle(.orange) }
                                }
                            }.accessibilityIdentifier("calendar.connection.item.\(item.id)")
                        }
                    }
                }
            }
            .disabled(service.busy)
            .navigationTitle("Calendar Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("calendar.connection.done")
            } }
            .sheet(isPresented: $showNewList) { ListEditSheet(store: store) }
            .onAppear { listID = initialListID ?? ItemList.inboxId }
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
