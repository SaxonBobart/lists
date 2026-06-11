import SwiftUI
import UIKit

/// Document-style detail page for tasks, notes, and events (habits keep the
/// classic form — `ItemDetailSheet` routes). One scrollable page: the title at
/// the top, a collapsible options block beneath it, and the markdown body
/// editable inline below — the item *is* a page you scroll and type into.
///
/// Behavioural contract:
/// - **Live-apply.** No Save/Discard ceremony: control changes persist
///   immediately; title/body keystrokes are debounced and flushed on close.
/// - **Options fold to a fact strip.** Collapsed, the block reads as one
///   footnote line of facts ("Tomorrow 3pm · repeat Weekly · ⚑ · !!") so the
///   page stays a clean document without hiding state.
/// - **Per-type default + memory.** Notes open folded (straight into typing);
///   tasks/events open expanded. The last state per type is remembered.
struct ItemDocumentView: View {
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    @State private var draft: Item
    @State private var optionsExpanded: Bool
    @State private var editorMode: MarkdownEditorMode = .live

    /// Which inline picker is currently visible (see ItemDetailSheet for the
    /// same pattern — the row label toggles visibility, the switch toggles
    /// enable state).
    private enum ExpandedPicker { case none, date, time }
    @State private var expandedPicker: ExpandedPicker = .none

    // Sub-sheet presentation
    @State private var showRepeatCustom = false
    @State private var showEarlyCustom = false
    @State private var showTimeZonePicker = false
    @State private var showSectionPicker = false
    @State private var showingDeleteConfirm = false

    /// Pending debounced apply for title/body keystrokes.
    @State private var applyTask: Task<Void, Never>?

    init(item: Item, store: ItemStore) {
        self.store = store
        _draft = State(initialValue: item)
        _optionsExpanded = State(initialValue: Self.initialExpansion(for: item.type))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                titleRow
                optionsBlock
                DocumentBodyEditor(text: bodyBinding, mode: editorMode)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
        .background(ListsTokens.Background.base)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onDisappear { finalizeAndFlush() }
        .alert("Delete this item?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\"\(draft.title)\" will move to Recently Deleted.")
        }
        .sheet(isPresented: $showRepeatCustom) {
            CustomRepeatSheet(initialRRule: parsedRepeat.custom,
                              startDate: draft.due ?? .now) { rrule in
                setRecurrence(base: rrule, until: parsedRepeat.until)
            }
        }
        .sheet(isPresented: $showEarlyCustom) {
            EarlyReminderCustomSheet(
                initialValue: draft.reminder?.early?.value ?? 5,
                initialUnit: draft.reminder?.early?.unit ?? .minute
            ) { value, unit in
                setEarlyReminder(EarlyReminder(value: value, unit: unit))
            }
        }
        .sheet(isPresented: $showTimeZonePicker) {
            TimeZonePickerSheet(identifier: timeZoneBinding)
        }
        .sheet(isPresented: $showSectionPicker) {
            SectionPickerSheet(store: store, listId: draft.listId, section: sectionBinding)
                .tint(.primary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            DetailSheetHeaderTitle(item: draft, store: store, standaloneLabel: typeDisplayName)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    editorMode = editorMode == .live ? .raw : .live
                } label: {
                    if editorMode == .raw {
                        Label("Live Formatting", systemImage: "textformat")
                    } else {
                        Label("Raw Markdown", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Item", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityLabel("More")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("document.menu")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                finalizeAndFlush()
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .accessibilityLabel("Done")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("document.done")
        }
    }

    // MARK: - Title row

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingControl
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: titleBinding, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1...6)
                    .foregroundStyle(draft.isComplete ? ListsTokens.Foreground.secondary
                                                      : ListsTokens.Foreground.primary)
                    .accessibilityIdentifier("document.title")
                TagInputView(tags: tagsBinding)
                    .accessibilityIdentifier("document.tags")
            }
        }
    }

    /// Same leading-control grammar as `ItemRow`: checkbox for a task or a
    /// completable event, calendar glyph for a plain event, document glyph
    /// for a note.
    @ViewBuilder
    private var leadingControl: some View {
        switch draft.type {
        case .task:
            doneCheckbox
        case .event where draft.completable:
            doneCheckbox
        case .event:
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .center)
        case .note, .habit:
            Image(systemName: "text.document.fill")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .center)
        }
    }

    private var doneCheckbox: some View {
        Button {
            toggleDone()
        } label: {
            Image(systemName: draft.done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(draft.done ? ListsTokens.accent : ListsTokens.Foreground.tertiary)
                .frame(width: 28, alignment: .center)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(draft.done ? "Mark not done" : "Mark done")
        .accessibilityIdentifier("document.checkbox")
    }

    // MARK: - Options block

    private var optionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                setExpanded(!optionsExpanded)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: optionsExpanded ? "chevron.down" : "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("Details")
                        .font(ListsTypography.footnote)
                        .foregroundStyle(.secondary)
                    if !optionsExpanded {
                        factStrip
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.options.toggle")

            if optionsExpanded {
                scheduleCard
                if draft.due != nil {
                    repeatCard
                }
                detailsCard
            }
        }
    }

    /// Collapsed summary: the facts that are actually set, in one footnote
    /// line — date/time, event end, repeat cadence, priority, flag.
    private var factStrip: some View {
        HStack(spacing: 6) {
            if let date = ItemMetaLine.dateString(for: draft) {
                Text(date)
            }
            if draft.type == .event, let end = draft.end {
                Text("→ \(endSummary(end))")
            }
            if let rrule = draft.recurrence?.rrule {
                HStack(spacing: 3) {
                    Image(systemName: "repeat")
                    Text(RepeatPreset.summary(forRRule: rrule))
                }
            }
            if let bangs = priorityBangs {
                Text(bangs)
                    .foregroundStyle(priorityBangColor ?? .secondary)
            }
            if draft.flagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(ListsTokens.Semantic.warning)
            }
        }
        .font(ListsTypography.footnote)
        .foregroundStyle(ListsTokens.Foreground.secondary)
        .lineLimit(1)
    }

    /// Rounded options card — plain background card on the document surface.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Schedule card

    private var scheduleCard: some View {
        card {
            splitToggleRow(
                title: "Date",
                subtitle: draft.due != nil ? dateSubtitle : nil,
                systemImage: "calendar",
                isOn: hasDateBinding,
                tapTarget: draft.due != nil
                    ? { withAnimation(.smooth) { expandedPicker = expandedPicker == .date ? .none : .date } }
                    : nil
            )
            .accessibilityIdentifier("document.due")

            if draft.due != nil && expandedPicker == .date {
                DatePicker("Date", selection: dueBinding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(.blue)
            }

            Divider()

            splitToggleRow(
                title: draft.type == .event ? "Starts" : "Time",
                subtitle: hasTime ? timeSubtitle : nil,
                systemImage: "clock",
                isOn: hasTimeBinding,
                tapTarget: hasTime
                    ? { withAnimation(.smooth) { expandedPicker = expandedPicker == .time ? .none : .time } }
                    : nil
            )

            if hasTime && expandedPicker == .time {
                DatePicker("Time", selection: dueBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(.blue)
                    .frame(maxWidth: .infinity)

                Button {
                    showTimeZonePicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        Text("Time Zone")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(TimeZoneLabel.display(for: draft.dueTimeZone))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                            .font(.footnote)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if draft.type == .event, draft.due != nil {
                Divider()
                splitToggleRow(
                    title: "Ends",
                    subtitle: nil,
                    systemImage: "calendar.badge.clock",
                    isOn: hasEndBinding,
                    tapTarget: nil
                )
                .accessibilityIdentifier("document.ends")

                if draft.end != nil {
                    DatePicker(
                        "End",
                        selection: endBinding,
                        in: (draft.due ?? .distantPast)...,
                        displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date]
                    )
                    .labelsHidden()
                    .tint(.blue)
                    .padding(.bottom, 11)
                }
            }

            Divider()

            Toggle(isOn: reminderBinding) {
                rowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)
            .padding(.vertical, 7)

            Divider()

            Toggle(isOn: urgentBinding) {
                rowLabel(title: "Urgent", subtitle: nil, systemImage: "alarm.fill")
            }
            .tint(.green)
            .padding(.vertical, 7)
        }
    }

    // MARK: Repeat card

    private var repeatCard: some View {
        card {
            Menu {
                ForEach(RepeatPreset.taskOptions, id: \.self) { preset in
                    Button {
                        setRepeatPreset(preset)
                    } label: {
                        if preset == parsedRepeat.preset {
                            Label(preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(preset.displayName)
                        }
                    }
                }
            } label: {
                pickerRowLabel(
                    title: "Repeat",
                    value: currentRepeatDisplay,
                    systemImage: parsedRepeat.preset == .never ? "repeat.badge.xmark" : "repeat"
                )
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.repeat")

            if parsedRepeat.preset != .never {
                Divider()
                Toggle(isOn: endRepeatBinding) {
                    rowLabel(
                        title: "End Repeat",
                        subtitle: parsedRepeat.until.map(Self.longDate),
                        systemImage: "calendar.badge.minus"
                    )
                }
                .tint(.green)
                .padding(.vertical, 7)

                if parsedRepeat.until != nil {
                    DatePicker(
                        "",
                        selection: endRepeatDateBinding,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(.blue)
                }
            }

            if draft.reminder?.enabled == true {
                Divider()
                Menu {
                    ForEach(EarlyReminderPreset.allCases, id: \.self) { preset in
                        Button {
                            if preset == .custom {
                                showEarlyCustom = true
                            } else {
                                setEarlyReminder(preset.value)
                            }
                        } label: {
                            if preset == currentEarlyPreset {
                                Label(preset.displayName, systemImage: "checkmark")
                            } else {
                                Text(preset.displayName)
                            }
                        }
                    }
                } label: {
                    pickerRowLabel(
                        title: "Early Reminder",
                        value: currentEarlyDisplay,
                        systemImage: "clock.arrow.circlepath"
                    )
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Details card

    private var detailsCard: some View {
        card {
            Menu {
                ForEach([Item.ItemType.task, .note, .event], id: \.self) { type in
                    Button {
                        setType(type)
                    } label: {
                        if type == draft.type {
                            Label(Self.displayName(for: type), systemImage: "checkmark")
                        } else {
                            Label(Self.displayName(for: type), systemImage: Self.glyph(for: type))
                        }
                    }
                }
            } label: {
                pickerRowLabel(
                    title: "Type",
                    value: typeDisplayName,
                    systemImage: Self.glyph(for: draft.type)
                )
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.type")

            if draft.type == .event {
                Divider()
                Toggle(isOn: completableBinding) {
                    rowLabel(title: "Checkbox",
                             subtitle: draft.completable ? "Behaves like a task — can go overdue" : nil,
                             systemImage: "checkmark.circle")
                }
                .tint(.green)
                .padding(.vertical, 7)
                .accessibilityIdentifier("document.completable")
            }

            Divider()

            Toggle(isOn: flaggedBinding) {
                rowLabel(title: "Flag", subtitle: nil, systemImage: "flag")
            }
            .tint(.green)
            .padding(.vertical, 7)
            .accessibilityIdentifier("document.flag")

            Divider()

            Menu {
                ForEach(Item.Priority.allCases, id: \.self) { p in
                    Button {
                        draft.priority = p
                        applyNow()
                    } label: {
                        if p == draft.priority {
                            Label(Self.displayName(for: p), systemImage: "checkmark")
                        } else {
                            Text(Self.displayName(for: p))
                        }
                    }
                }
            } label: {
                pickerRowLabel(
                    title: "Priority",
                    value: Self.displayName(for: draft.priority),
                    systemImage: Self.priorityGlyph(for: draft.priority)
                )
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.priority")

            Divider()

            Button {
                showSectionPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.dashed")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                    Text("Section")
                        .foregroundStyle(.primary)
                    Spacer()
                    if let name = resolvedSectionName, !name.isEmpty {
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .font(.footnote)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.section")

            Divider()

            Menu {
                ForEach(activeLists, id: \.id) { list in
                    Button {
                        draft.listId = list.id
                        draft.section = nil
                        applyNow()
                    } label: {
                        if list.id == draft.listId {
                            Label(list.name, systemImage: "checkmark")
                        } else {
                            Label(list.name, systemImage: list.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if let list = selectedList {
                        IconBadge(
                            systemName: list.icon,
                            hue: ListsTokens.listColor(list.color),
                            size: 24,
                            glyphSize: 12,
                            shape: .circle
                        )
                    } else {
                        Image(systemName: "tray.fill")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                    }
                    Text("List")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(selectedList?.name ?? "")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .font(.footnote)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(.primary)
            .accessibilityIdentifier("document.list")
        }
    }

    // MARK: - Row label helpers (mirror the form sheets)

    private func rowLabel(title: String, subtitle: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.blue)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func pickerRowLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
                .font(.footnote)
        }
    }

    /// Label-tap expands the inline picker; the switch flips enable state.
    private func splitToggleRow(
        title: String,
        subtitle: String?,
        systemImage: String,
        isOn: Binding<Bool>,
        tapTarget: (() -> Void)?
    ) -> some View {
        HStack(spacing: 0) {
            if let tapTarget {
                Button(action: tapTarget) {
                    rowLabel(title: title, subtitle: subtitle, systemImage: systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
            } else {
                rowLabel(title: title, subtitle: subtitle, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.green)
        }
        .padding(.vertical, 7)
    }

    // MARK: - Live-apply plumbing

    /// Apply the draft to the store immediately (no-op when nothing changed,
    /// or when the item has been deleted out from under the page).
    private func applyNow() {
        applyTask?.cancel()
        applyTask = nil
        guard let live = store.item(draft.id), live.deletedAt == nil else { return }
        var candidate = draft
        candidate.modifiedAt = live.modifiedAt
        guard candidate != live else { return }
        store.applyUpdateSync(draft)
        if let updated = store.item(draft.id) {
            draft.modifiedAt = updated.modifiedAt
        }
    }

    /// Debounced apply for title/body keystrokes — each change re-arms the
    /// timer with a fresh snapshot, so the last keystroke wins.
    private func scheduleApply() {
        applyTask?.cancel()
        let snapshot = draft
        applyTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            guard let live = store.item(snapshot.id), live.deletedAt == nil else { return }
            var candidate = snapshot
            candidate.modifiedAt = live.modifiedAt
            guard candidate != live else { return }
            store.applyUpdateSync(snapshot)
        }
    }

    /// Closing flush: extract any `#tag` typed into the title, then apply.
    private func finalizeAndFlush() {
        let (cleaned, parsed) = Tag.extractInline(from: draft.title)
        if !parsed.isEmpty {
            for tag in parsed {
                draft.tags = Tag.appending(tag, to: draft.tags)
            }
            if !cleaned.isEmpty { draft.title = cleaned }
        }
        applyNow()
    }

    /// Done goes through `toggleDone` (not a raw field write) so recurrence
    /// spawning and completion stamps behave exactly like the row checkbox.
    private func toggleDone() {
        finalizeAndFlush()
        Task {
            try? await store.toggleDone(draft.id)
            if let live = store.item(draft.id) {
                draft = live
            }
        }
    }

    private func delete() {
        applyTask?.cancel()
        applyTask = nil
        Task {
            try? await store.softDelete(draft.id)
            dismiss()
        }
    }

    // MARK: - Bindings

    private var titleBinding: Binding<String> {
        Binding(
            get: { draft.title },
            set: { draft.title = $0; scheduleApply() }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { draft.body },
            set: { draft.body = $0; scheduleApply() }
        )
    }

    private var tagsBinding: Binding<[String]> {
        Binding(
            get: { draft.tags },
            set: { draft.tags = $0; applyNow() }
        )
    }

    private var sectionBinding: Binding<String?> {
        Binding(
            get: { draft.section },
            set: { draft.section = $0; applyNow() }
        )
    }

    private var timeZoneBinding: Binding<String?> {
        Binding(
            get: { draft.dueTimeZone },
            set: { draft.dueTimeZone = $0; applyNow() }
        )
    }

    private var flaggedBinding: Binding<Bool> {
        Binding(
            get: { draft.flagged },
            set: { draft.flagged = $0; applyNow() }
        )
    }

    private var hasTime: Bool { draft.due != nil && !draft.dueAllDay }

    /// Date on → seed a friendly due + auto-enable Reminder (mirrors the form
    /// sheets' cascades). Date off → everything hanging off the date goes too.
    private var hasDateBinding: Binding<Bool> {
        Binding(
            get: { draft.due != nil },
            set: { newValue in
                withAnimation(.smooth) {
                    if newValue {
                        draft.due = draft.due ?? Self.defaultDue()
                        draft.dueAllDay = true
                        if draft.reminder?.enabled != true {
                            draft.reminder = Reminder(enabled: true, early: nil)
                        }
                        expandedPicker = .date
                    } else {
                        draft.due = nil
                        draft.dueAllDay = false
                        draft.end = nil
                        draft.reminder = nil
                        draft.triggers = nil
                        draft.recurrence = nil
                        expandedPicker = .none
                    }
                }
                applyNow()
            }
        )
    }

    private var hasTimeBinding: Binding<Bool> {
        Binding(
            get: { hasTime },
            set: { newValue in
                withAnimation(.smooth) {
                    if newValue {
                        draft.due = draft.due ?? Self.defaultDue()
                        draft.dueAllDay = false
                        if draft.reminder?.enabled != true {
                            draft.reminder = Reminder(enabled: true, early: nil)
                        }
                        expandedPicker = .time
                    } else {
                        draft.dueAllDay = draft.due != nil
                        draft.triggers = nil
                        expandedPicker = .none
                    }
                }
                applyNow()
            }
        )
    }

    private var dueBinding: Binding<Date> {
        Binding(
            get: { draft.due ?? Self.defaultDue() },
            set: { newValue in
                // Keep a multi-day event's span: shift the end with the start.
                if let end = draft.end, let due = draft.due {
                    draft.end = end.addingTimeInterval(newValue.timeIntervalSince(due))
                }
                draft.due = newValue
                applyNow()
            }
        )
    }

    private var hasEndBinding: Binding<Bool> {
        Binding(
            get: { draft.end != nil },
            set: { newValue in
                withAnimation(.smooth) {
                    if newValue {
                        let start = draft.due ?? Self.defaultDue()
                        draft.end = draft.dueAllDay
                            ? Calendar.current.date(byAdding: .day, value: 1, to: start)
                            : start.addingTimeInterval(3600)
                    } else {
                        draft.end = nil
                    }
                }
                applyNow()
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { draft.end ?? draft.due ?? .now },
            set: { draft.end = $0; applyNow() }
        )
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { draft.reminder?.enabled ?? false },
            set: { newValue in
                withAnimation(.smooth) {
                    if newValue {
                        if draft.due == nil {
                            draft.due = Self.defaultDue()
                            draft.dueAllDay = true
                        }
                        draft.reminder = Reminder(enabled: true, early: draft.reminder?.early)
                    } else {
                        draft.reminder = nil
                        draft.triggers = nil
                    }
                }
                applyNow()
            }
        )
    }

    private var urgentBinding: Binding<Bool> {
        Binding(
            get: { draft.triggers?.urgent?.enabled ?? false },
            set: { newValue in
                withAnimation(.smooth) {
                    if newValue {
                        if draft.due == nil {
                            draft.due = Self.defaultDue()
                        }
                        draft.dueAllDay = false
                        if draft.reminder?.enabled != true {
                            draft.reminder = Reminder(enabled: true, early: draft.reminder?.early)
                        }
                        draft.triggers = Triggers(urgent: TriggerToggle(enabled: true))
                    } else {
                        draft.triggers = nil
                    }
                }
                applyNow()
            }
        )
    }

    private var completableBinding: Binding<Bool> {
        Binding(
            get: { draft.completable },
            set: { newValue in
                draft.completable = newValue
                if !newValue {
                    draft.done = false
                    draft.completedAt = nil
                }
                applyNow()
            }
        )
    }

    // MARK: - Recurrence plumbing

    /// Current recurrence decomposed into preset + custom base + UNTIL date,
    /// re-derived from the draft on every read so the controls and the model
    /// can't drift apart.
    private var parsedRepeat: (preset: RepeatPreset, custom: String?, until: Date?) {
        guard let rrule = draft.recurrence?.rrule, !rrule.isEmpty else { return (.never, nil, nil) }
        var base = rrule
        var until: Date? = nil
        if let untilRange = rrule.range(of: ";UNTIL=") {
            until = Self.parseUntil(String(rrule[untilRange.upperBound...]))
            base = String(rrule[rrule.startIndex..<untilRange.lowerBound])
        }
        for preset in RepeatPreset.taskOptions where preset != .custom && preset != .never {
            if preset.rrule == base {
                return (preset, nil, until)
            }
        }
        return (.custom, base, until)
    }

    private func setRepeatPreset(_ preset: RepeatPreset) {
        switch preset {
        case .never:
            draft.recurrence = nil
            applyNow()
        case .custom:
            showRepeatCustom = true
        default:
            setRecurrence(base: preset.rrule, until: parsedRepeat.until)
        }
    }

    private func setRecurrence(base: String?, until: Date?) {
        guard let base, !base.isEmpty else {
            draft.recurrence = nil
            applyNow()
            return
        }
        if let until {
            draft.recurrence = Recurrence(rrule: "\(base);UNTIL=\(Self.formatUntil(until))")
        } else {
            draft.recurrence = Recurrence(rrule: base)
        }
        applyNow()
    }

    private var endRepeatBinding: Binding<Bool> {
        Binding(
            get: { parsedRepeat.until != nil },
            set: { newValue in
                let current = parsedRepeat
                withAnimation(.smooth) {
                    setRecurrence(
                        base: current.preset == .custom ? current.custom : current.preset.rrule,
                        until: newValue ? Self.defaultEndRepeat() : nil
                    )
                }
            }
        )
    }

    private var endRepeatDateBinding: Binding<Date> {
        Binding(
            get: { parsedRepeat.until ?? Self.defaultEndRepeat() },
            set: { newValue in
                let current = parsedRepeat
                setRecurrence(
                    base: current.preset == .custom ? current.custom : current.preset.rrule,
                    until: newValue
                )
            }
        )
    }

    private var currentRepeatDisplay: String {
        let current = parsedRepeat
        if current.preset == .custom {
            return current.custom.flatMap { RecurrenceRule.parse($0)?.shortLabel } ?? "Custom"
        }
        return current.preset.displayName
    }

    // MARK: - Early reminder plumbing

    private func setEarlyReminder(_ early: EarlyReminder?) {
        draft.reminder = Reminder(enabled: true, early: early)
        applyNow()
    }

    private var currentEarlyPreset: EarlyReminderPreset {
        guard let early = draft.reminder?.early else { return .none }
        for preset in EarlyReminderPreset.allCases where preset != .none && preset != .custom {
            if let v = preset.value, v.value == early.value && v.unit == early.unit {
                return preset
            }
        }
        return .custom
    }

    private var currentEarlyDisplay: String {
        if currentEarlyPreset == .custom {
            return CustomEarlyReminder.displayName(for: draft.reminder?.early)
        }
        return currentEarlyPreset.displayName
    }

    // MARK: - Type switching

    /// Type-flip rule (same as the form sheet): task → event keeps its
    /// checkbox via `completable`; flips that lose the checkbox clear the
    /// done state so it can't linger invisibly.
    private func setType(_ newType: Item.ItemType) {
        let old = draft.type
        guard newType != old else { return }
        draft.type = newType
        if newType == .event && old == .task {
            draft.completable = true
        }
        let keepsDone = newType == .task || (newType == .event && draft.completable)
        if !keepsDone {
            draft.done = false
            draft.completedAt = nil
        }
        applyNow()
    }

    // MARK: - Options expansion memory

    private static func expansionKey(_ type: Item.ItemType) -> String {
        "document.options.expanded.\(type.rawValue)"
    }

    /// Notes open folded (straight into typing); scheduled types open
    /// expanded. After the first visit, the last state per type wins.
    static func initialExpansion(for type: Item.ItemType) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: expansionKey(type)) == nil {
            return type != .note
        }
        return defaults.bool(forKey: expansionKey(type))
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.smooth) { optionsExpanded = expanded }
        UserDefaults.standard.set(expanded, forKey: Self.expansionKey(draft.type))
    }

    // MARK: - Computed display helpers

    private var typeDisplayName: String { Self.displayName(for: draft.type) }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var selectedList: ItemList? {
        store.lists.first { $0.id == draft.listId }
    }

    private var resolvedSectionName: String? {
        guard let s = draft.section, !s.isEmpty else { return nil }
        return selectedList?.sections.first { $0.id.uuidString == s }?.name
    }

    private var priorityBangs: String? {
        switch draft.priority {
        case .high:   return "!!!"
        case .medium: return "!!"
        case .low:    return "!"
        case .none:   return nil
        }
    }

    private var priorityBangColor: Color? {
        switch draft.priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        case .none:   return nil
        }
    }

    private var dateSubtitle: String {
        guard let due = draft.due else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(due)    { return "Today" }
        if cal.isDateInTomorrow(due) { return "Tomorrow" }
        return Self.longDate(due)
    }

    private var timeSubtitle: String {
        guard let due = draft.due else { return "" }
        return due.formatted(date: .omitted, time: .shortened)
    }

    /// Compact end-of-span summary for the fact strip: time-only when the
    /// event ends the same day it starts, otherwise a short date.
    private func endSummary(_ end: Date) -> String {
        if let due = draft.due, Calendar.current.isDate(end, inSameDayAs: due), !draft.dueAllDay {
            return end.formatted(date: .omitted, time: .shortened)
        }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: end)
    }

    private static func displayName(for type: Item.ItemType) -> String {
        switch type {
        case .task:  return "Task"
        case .note:  return "Note"
        case .habit: return "Habit"
        case .event: return "Event"
        }
    }

    private static func glyph(for type: Item.ItemType) -> String {
        switch type {
        case .task:  return "circle"
        case .note:  return "text.document"
        case .habit: return "checkmark.arrow.trianglehead.clockwise"
        case .event: return "calendar"
        }
    }

    private static func displayName(for p: Item.Priority) -> String {
        switch p {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    private static func priorityGlyph(for p: Item.Priority) -> String {
        switch p {
        case .none:   return "exclamationmark.circle"
        case .low:    return "exclamationmark"
        case .medium: return "exclamationmark.2"
        case .high:   return "exclamationmark.3"
        }
    }

    private static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: date)
    }

    private static func defaultDue() -> Date {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        return cal.date(byAdding: .hour, value: 9, to: startOfToday) ?? .now
    }

    private static func defaultEndRepeat() -> Date {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        return cal.date(byAdding: .month, value: 6, to: startOfToday) ?? .now
    }

    private static func formatUntil(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private static func parseUntil(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        if let d = f.date(from: s) { return d }
        let day = DateFormatter()
        day.dateFormat = "yyyyMMdd"
        return day.date(from: s)
    }
}

// MARK: - Inline document body editor

/// The markdown editor embedded in the document page: the same styler /
/// layout-manager / coordinator stack as `MarkdownTextView`, but
/// **non-scrolling and self-sizing** so the page is one continuous scroll.
/// The editor reports its fitted height through `sizeThatFits`, and the
/// coordinator's `onEditorInteraction` hook keeps the caret visible inside
/// the enclosing SwiftUI scroll view (a non-scrolling text view can't).
private struct DocumentBodyEditor: UIViewRepresentable {
    @Binding var text: String
    var mode: MarkdownEditorMode = .live
    /// Generous floor so an empty body still reads as "tap here and type".
    var minHeight: CGFloat = 220
    /// Aligns body text under the title text (28pt control rail + 12pt gap).
    var leadingInset: CGFloat = 40

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        context.coordinator.layoutDelegate.styler = storage
        layout.delegate = context.coordinator.layoutDelegate
        storage.glyphInvalidatable = layout

        let textView = MarkdownInternalTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.indentDelegate = context.coordinator
        textView.markdownPasteDelegate = context.coordinator
        textView.arrowDelegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.textContainerInset = UIEdgeInsets(top: 10, left: leadingInset, bottom: 24, right: 0)
        // Markdown source must be preserved verbatim — see MarkdownTextView.
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityIdentifier = "document.body"
        textView.inputAccessoryView = MarkdownReminderToolbar(coordinator: context.coordinator)

        // Tap-to-toggle for task checkboxes — same wiring as MarkdownTextView
        // (see there for why allowedTouchTypes and require(toFail:) matter).
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(EditorCoordinator.handleCheckboxTap(_:))
        )
        tap.delegate = context.coordinator
        tap.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.indirect.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        tap.cancelsTouchesInView = true
        textView.addGestureRecognizer(tap)
        for existing in (textView.gestureRecognizers ?? []) where existing !== tap {
            if existing is UITapGestureRecognizer {
                existing.require(toFail: tap)
            }
        }

        // Hidden XCUITest hook exposing the selectedRange (see MarkdownTextView).
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-data")
        let cursorIndicator = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        cursorIndicator.isAccessibilityElement = isUITesting
        cursorIndicator.accessibilityElementsHidden = !isUITesting
        cursorIndicator.accessibilityIdentifier = "document.body.cursor"
        cursorIndicator.alpha = 0
        cursorIndicator.accessibilityValue = "0-0"
        textView.addSubview(cursorIndicator)
        context.coordinator.cursorIndicator = cursorIndicator
        context.coordinator.textViewRef = textView

        if !text.isEmpty {
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        }
        storage.mode = mode

        context.coordinator.onEditorInteraction = { [weak textView] in
            guard let textView else { return }
            Self.scheduleCaretReveal(for: textView)
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard let storage = uiView.textStorage as? MarkdownStyler else { return }
        if uiView.text != text {
            let diff = TextDiff.minimal(from: storage.string, to: text)
            storage.replaceCharacters(in: diff.range, with: diff.replacement)
        }
        if storage.mode != mode {
            storage.mode = mode
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // Width-stable measurement — trust a real proposed width, remember it,
        // and decline to size before one exists (see InlineItemEditor for the
        // "phantom extra line" this prevents).
        let proposed = proposal.width ?? 0
        let width: CGFloat
        if proposed > 1 {
            width = proposed
            context.coordinator.lastMeasuredWidth = proposed
        } else if context.coordinator.lastMeasuredWidth > 1 {
            width = context.coordinator.lastMeasuredWidth
        } else {
            return nil
        }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(ceil(fitted.height), minHeight))
    }

    /// Scroll the enclosing (SwiftUI) scroll view so the caret stays visible.
    /// Deferred one runloop so the page's self-sizing pass lands first — the
    /// caret's new position only exists after the editor has grown.
    private static func scheduleCaretReveal(for textView: UITextView) {
        DispatchQueue.main.async { [weak textView] in
            guard let textView,
                  textView.isFirstResponder,
                  let scrollView = textView.enclosingDocumentScrollView,
                  let selectedEnd = textView.selectedTextRange?.end else { return }
            var caret = textView.caretRect(for: selectedEnd)
            guard caret.origin.y.isFinite, caret.height > 0 else { return }
            caret = caret.insetBy(dx: 0, dy: -40)
            scrollView.scrollRectToVisible(scrollView.convert(caret, from: textView), animated: false)
        }
    }
}

private extension UIView {
    /// Nearest ancestor scroll view — the SwiftUI ScrollView's backing view.
    /// (The text view itself inherits from UIScrollView, so the walk starts
    /// at the superview.)
    var enclosingDocumentScrollView: UIScrollView? {
        var node = superview
        while let current = node {
            if let scroll = current as? UIScrollView { return scroll }
            node = current.superview
        }
        return nil
    }
}
