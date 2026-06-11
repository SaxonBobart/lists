import SwiftUI
import UIKit

/// Document-style detail page for tasks, notes, and events (habits keep the
/// classic form — `ItemDetailSheet` routes). One scrollable page: the title at
/// the top, a one-line fact strip beneath it, and the markdown body editable
/// inline below — the item *is* a page you scroll and type into.
///
/// Behavioural contract:
/// - **Live-apply.** No Save/Discard ceremony: control changes persist
///   immediately; title/body keystrokes are debounced and flushed on close.
/// - **Facts stay on the page.** The strip under the title shows what's set
///   (date/time, event end, repeat cadence, priority, flag) exactly like a
///   row's meta line. The full controls live in a Details sheet, opened from
///   the ⓘ in the nav bar or by tapping the strip.
/// - **Quick bar on the title.** While editing the title, a glass keyboard
///   bar offers the fast edits (flag, priority, type, open Details) without
///   leaving the keyboard. Return hops into the body.
/// Navigation value for the breadcrumb menu — pushes an ancestor's document
/// page onto the hosting `ItemDetailSheet` stack.
struct BreadcrumbDestination: Hashable {
    let id: UUID
}

struct ItemDocumentView: View {
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    @State private var draft: Item
    @State private var editorMode: MarkdownEditorMode = .live
    /// One sheet at a time — the Details controls or the breadcrumb path.
    private enum ActiveSheet: Int, Identifiable { case details, breadcrumb; var id: Int { rawValue } }
    @State private var activeSheet: ActiveSheet?
    /// True while a field on this page holds the keyboard — the hide-keyboard
    /// tick only shows then (like the inline editor's Done on the list screens).
    /// Driven by keyboard show/hide notifications (observation only; no inset
    /// handling, so it doesn't touch UIKit's keyboard avoidance).
    @State private var isEditing = false
    /// The hosting stack's path, so the breadcrumb menu can push an ancestor's
    /// own document page. Nil outside a navigation stack (previews) — the
    /// breadcrumb entry just no-ops then.
    private let path: Binding<NavigationPath>?
    /// First-responder plumbing between the title and body text views (both
    /// UIKit representables — SwiftUI focus state can't reach them).
    @State private var focusBridge = DocumentFocusBridge()

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

    init(item: Item, store: ItemStore, path: Binding<NavigationPath>? = nil) {
        self.store = store
        self.path = path
        _draft = State(initialValue: item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                titleRow
                factStripRow
                Divider()
                    .padding(.top, 4)
                DocumentBodyEditor(text: bodyBinding, mode: editorMode, bridge: focusBridge)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
        .background(ListsTokens.Background.base)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isEditing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isEditing = false
        }
        .onAppear { normalizeEventDates() }
        .onDisappear { finalizeAndFlush() }
        .alert("Delete this item?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\"\(draft.title)\" will move to Recently Deleted.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .details:    detailsSheet
            case .breadcrumb: breadcrumbSheet
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                leavePage()
            } label: {
                Image(systemName: "chevron.backward")
                    .accessibilityLabel("Back")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("document.back")
        }
        ToolbarItem(placement: .principal) {
            breadcrumbTitle
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                openDetails()
            } label: {
                Image(systemName: "info.circle")
                    .accessibilityLabel("Details")
            }
            .tint(Color.primary)
            .accessibilityIdentifier("document.info")
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
        if isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    focusBridge.endEditing()
                } label: {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Hide Keyboard")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(ListsTokens.accent)
                .accessibilityIdentifier("document.done")
            }
        }
    }

    /// Leave the page (the leading back button). Flush edits, then dismiss.
    private func leavePage() {
        finalizeAndFlush()
        dismiss()
    }

    /// Open the Details sheet — the keyboard resigns first so the sheet isn't
    /// fighting an active text view underneath it.
    private func openDetails() {
        focusBridge.endEditing()
        activeSheet = .details
    }

    // MARK: - Breadcrumb

    /// The principal title. When the item sits in a thread — it has a parent OR
    /// children — it's a tappable label (type name + chevron) that opens the
    /// breadcrumb as a sheet from the bottom. A standalone item is a plain label.
    @ViewBuilder
    private var breadcrumbTitle: some View {
        if hasThread {
            Button {
                focusBridge.endEditing()
                activeSheet = .breadcrumb
            } label: {
                HStack(spacing: 4) {
                    Text(typeDisplayName)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(ListsTypography.headline)
                .foregroundStyle(ListsTokens.Foreground.primary)
            }
            .accessibilityIdentifier("document.breadcrumb")
        } else {
            Text(typeDisplayName)
                .font(ListsTypography.headline)
                .foregroundStyle(ListsTokens.Foreground.primary)
        }
    }

    /// Shown whenever the item is part of a thread, so a top-level parent (no
    /// ancestors but with children) still exposes the breadcrumb.
    private var hasThread: Bool { !ancestors.isEmpty || !children.isEmpty }

    /// The item's ancestor chain (root → … → immediate parent), oldest first.
    /// Empty for a top-level item.
    private var ancestors: [Item] {
        var chain: [Item] = []
        var parentId = draft.parentId
        while let pid = parentId,
              let parent = store.items.first(where: { $0.id == pid && $0.deletedAt == nil }) {
            chain.insert(parent, at: 0)
            parentId = parent.parentId
        }
        return chain
    }

    /// Direct children of this item, for jumping *down* the thread from the
    /// breadcrumb sheet.
    private var children: [Item] {
        store.items
            .filter { $0.parentId == draft.id && $0.deletedAt == nil }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private func breadcrumbLabel(_ item: Item) -> String {
        item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled" : item.title
    }

    /// The breadcrumb as a bottom sheet: the ancestor chain, this item (marked
    /// "Current"), then its direct children — tapping any other row jumps to
    /// that item's own document page, so you can move up or down the thread.
    private var breadcrumbSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(ancestors.enumerated()), id: \.element.id) { index, ancestor in
                    Button {
                        openBreadcrumb(ancestor.id)
                    } label: {
                        breadcrumbRow(ancestor, depth: index, isCurrent: false)
                    }
                    .buttonStyle(.plain)
                }
                breadcrumbRow(draft, depth: ancestors.count, isCurrent: true)
                ForEach(children) { child in
                    Button {
                        openBreadcrumb(child.id)
                    } label: {
                        breadcrumbRow(child, depth: ancestors.count + 1, isCurrent: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Breadcrumb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { activeSheet = nil }
                        .tint(.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func breadcrumbRow(_ item: Item, depth: Int, isCurrent: Bool) -> some View {
        HStack(spacing: 8) {
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 16)
                Image(systemName: "arrow.turn.down.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            Text(breadcrumbLabel(item))
                .foregroundStyle(isCurrent ? ListsTokens.Foreground.secondary
                                           : ListsTokens.Foreground.primary)
            Spacer()
            if isCurrent {
                Text("Current")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    /// Jump to an ancestor's own document page (pushed onto this stack). Flush
    /// pending edits first so nothing typed here is lost on the way up.
    private func openBreadcrumb(_ id: UUID) {
        focusBridge.endEditing()
        finalizeAndFlush()
        activeSheet = nil
        path?.wrappedValue.append(BreadcrumbDestination(id: id))
    }

    // MARK: - Title row

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsLeadingControl {
                doneCheckbox
            }
            VStack(alignment: .leading, spacing: 6) {
                DocumentTitleField(
                    text: titleBinding,
                    textColor: UIColor(draft.isComplete ? ListsTokens.Foreground.secondary
                                                        : ListsTokens.Foreground.primary),
                    quickState: DocumentQuickState(
                        flagged: draft.flagged,
                        priority: draft.priority,
                        type: draft.type
                    ),
                    onToggleFlag: { draft.flagged.toggle(); applyNow() },
                    onSetPriority: { draft.priority = $0; applyNow() },
                    onSetType: { setType($0) },
                    onOpenDetails: { openDetails() },
                    bridge: focusBridge
                )
                TagInputView(tags: tagsBinding)
                    .accessibilityIdentifier("document.tags")
            }
        }
    }

    /// Only a *functional* control gets a leading slot on the page: the
    /// checkbox of a task or a completable event. A note or a plain event has
    /// only a decorative glyph, which is redundant here (the type already shows
    /// in the nav bar), so it's hidden and the title sits flush at the margin.
    private var showsLeadingControl: Bool {
        draft.type == .task || (draft.type == .event && draft.completable)
    }

    private var doneCheckbox: some View {
        Button {
            toggleDone()
        } label: {
            Image(systemName: draft.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(draft.done ? ListsTokens.accent : ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28, alignment: .leading)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(draft.done ? "Mark not done" : "Mark done")
        .accessibilityIdentifier("document.checkbox")
    }

    // MARK: - Fact strip

    /// The page's property line: the facts that are actually set, rendered
    /// like a row's meta line, aligned under the title text. Tapping it opens
    /// the Details sheet. Hidden entirely when nothing is set — the ⓘ stays
    /// the way in.
    @ViewBuilder
    private var factStripRow: some View {
        if hasFacts {
            Button {
                openDetails()
            } label: {
                factStrip
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.facts")
            // Align under the title text: 28pt rail + 12pt gap when a checkbox
            // is shown; flush at the margin when the title is (note / event).
            .padding(.leading, showsLeadingControl ? 40 : 0)
        }
    }

    private var hasFacts: Bool {
        draft.due != nil
            || draft.recurrence?.rrule != nil
            || draft.priority != Item.Priority.none
            || draft.flagged
    }

    /// Overdue per the rows' shared rule (`due` before the start of today),
    /// so the strip's date turns the same red the row's meta line does.
    private var isOverdue: Bool {
        guard let due = draft.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    private var factStrip: some View {
        HStack(spacing: 6) {
            if let date = ItemMetaLine.dateString(for: draft) {
                Text(date)
                    .foregroundStyle(isOverdue && !draft.isComplete
                                     ? ListsTokens.Semantic.danger
                                     : ListsTokens.Foreground.secondary)
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

    // MARK: - Details sheet

    /// All the item's controls, as a pop-up over the document rather than a
    /// block inside it: schedule, repeat, and details cards — the same cards
    /// the form sheets use, live-applying like everything else on the page.
    private var detailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    scheduleCard
                    if draft.due != nil {
                        repeatCard
                    }
                    detailsCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ListsTokens.Background.base)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = nil
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .accessibilityLabel("Done")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(ListsTokens.accent)
                    .accessibilityIdentifier("document.details.done")
                }
            }
            // Sub-editors present over the Details sheet, so their modifiers
            // hang off its content (a sheet modifier on the underlying page
            // couldn't present while Details is up).
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Rounded options card — plain background card on the sheet surface.
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
            if draft.type == .event {
                eventDateRows
            } else {
                taskDateRows
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

    /// Event scheduling, Apple Calendar style: Starts / Ends each show a date
    /// pill (plus a time pill unless All Day is on), and an All Day toggle that
    /// drops the time components. Start/end are mandatory (see `ensureEventDates`).
    @ViewBuilder
    private var eventDateRows: some View {
        HStack {
            Text("Starts").foregroundStyle(.primary)
            Spacer(minLength: 12)
            DatePicker("", selection: dueBinding,
                       displayedComponents: draft.dueAllDay ? [.date] : [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(ListsTokens.accent)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("document.due")

        Divider()

        HStack {
            Text("Ends").foregroundStyle(.primary)
            Spacer(minLength: 12)
            DatePicker("", selection: endBinding,
                       in: (draft.due ?? .distantPast)...,
                       displayedComponents: draft.dueAllDay ? [.date] : [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(ListsTokens.accent)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("document.ends")

        Divider()

        Toggle(isOn: allDayBinding) {
            rowLabel(title: "All Day", subtitle: nil, systemImage: "calendar")
        }
        .tint(.green)
        .padding(.vertical, 7)
        .accessibilityIdentifier("document.allday")
    }

    /// Task scheduling: optional Date + Time toggle rows with expanding pickers.
    @ViewBuilder
    private var taskDateRows: some View {
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
            title: "Time",
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
                    rowLabel(title: "Completable", subtitle: nil, systemImage: "checkmark.circle")
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
                // An event must keep a start date — ignore turning Date off.
                if !newValue && draft.type == .event { return }
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
                // An event must keep an end date — ignore turning Ends off.
                if !newValue && draft.type == .event { return }
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

    /// All-day toggle for events: flips `dueAllDay`, which drops the time pills
    /// from the Starts/Ends pickers. Start + end stay set either way.
    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { draft.dueAllDay },
            set: { newValue in
                withAnimation(.smooth) { draft.dueAllDay = newValue }
                applyNow()
            }
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

    /// Type-flip rule: an event is a calendar block — switching to Event makes
    /// it a plain (non-completable) event so its glyph becomes the calendar, and
    /// guarantees it has a start + end. Flips that lose the checkbox clear the
    /// done state so it can't linger invisibly.
    private func setType(_ newType: Item.ItemType) {
        let old = draft.type
        guard newType != old else { return }
        draft.type = newType
        if newType == .event {
            draft.completable = false
            ensureEventDates()
        }
        let keepsDone = newType == .task || (newType == .event && draft.completable)
        if !keepsDone {
            draft.done = false
            draft.completedAt = nil
        }
        applyNow()
    }

    /// An event must always have a start and an end. Seed sensible defaults for
    /// whichever is missing (next top-of-the-hour start, +1h end), preserving
    /// any start the item already carried.
    private func ensureEventDates() {
        let cal = Calendar.current
        if draft.due == nil {
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: Date())
            let flooredHour = cal.date(from: comps) ?? Date()
            draft.due = cal.date(byAdding: .hour, value: 1, to: flooredHour) ?? Date()
            draft.dueAllDay = false
        }
        if draft.end == nil, let start = draft.due {
            draft.end = draft.dueAllDay
                ? (cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
                : start.addingTimeInterval(3_600)
        }
    }

    /// Run on open so an event that predates the start+end rule (or arrived from
    /// elsewhere without an end) is normalised. No-op for non-events.
    private func normalizeEventDates() {
        guard draft.type == .event else { return }
        ensureEventDates()
        applyNow()
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

// MARK: - Focus bridge

/// First-responder plumbing between the page's two UIKit text views. SwiftUI
/// focus state can't reach inside representables, so both register here and
/// the page (or the quick bar) drives focus through it.
@MainActor
final class DocumentFocusBridge {
    weak var titleView: UITextView?
    weak var bodyView: UITextView?

    /// Return in the title hops into the body, caret at the start.
    func focusBody() {
        guard let bodyView else { return }
        bodyView.becomeFirstResponder()
        let start = bodyView.beginningOfDocument
        bodyView.selectedTextRange = bodyView.textRange(from: start, to: start)
    }

    func endEditing() {
        titleView?.resignFirstResponder()
        bodyView?.resignFirstResponder()
    }
}

// MARK: - Quick details bar

/// Snapshot of the item state the quick bar displays.
private struct DocumentQuickState: Equatable {
    var flagged: Bool
    var priority: Item.Priority
    var type: Item.ItemType
}

/// The title's keyboard accessory: the same Liquid Glass pill as the inline
/// editor's bar, carrying the fast metadata edits — open Details, flag,
/// priority, type — so a quick flag doesn't force a trip into the sheet.
private final class DocumentQuickDetailsBar: KeyboardGlassBar {
    var onOpenDetails: () -> Void = {}
    var onToggleFlag: () -> Void = {}
    var onSetPriority: (Item.Priority) -> Void = { _ in }
    var onSetType: (Item.ItemType) -> Void = { _ in }

    private let stackView = UIStackView()
    private let detailsButton = UIButton(type: .system)
    private let flagButton = UIButton(type: .system)
    private let priorityButton = UIButton(type: .system)
    private let typeButton = UIButton(type: .system)
    private var state = DocumentQuickState(flagged: false, priority: .none, type: .task)

    static func make() -> DocumentQuickDetailsBar {
        let bar = DocumentQuickDetailsBar()
        bar.setupContent()
        return bar
    }

    private func setupContent() {
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        pillContent.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: pillContent.leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: pillContent.trailingAnchor, constant: -14),
            stackView.centerYAnchor.constraint(equalTo: pillContent.centerYAnchor)
        ])

        configureCircularButton(detailsButton, symbol: "calendar.badge.clock", id: "document.quickbar.date")
        detailsButton.addAction(UIAction { [weak self] _ in
            self?.onOpenDetails()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(detailsButton)

        configureCircularButton(flagButton, symbol: "flag", id: "document.quickbar.flag")
        flagButton.addAction(UIAction { [weak self] _ in
            self?.onToggleFlag()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(flagButton)

        configureCircularButton(priorityButton, symbol: "exclamationmark.circle", id: "document.quickbar.priority")
        priorityButton.showsMenuAsPrimaryAction = true
        stackView.addArrangedSubview(priorityButton)

        configureCircularButton(typeButton, symbol: "circle", id: "document.quickbar.type")
        typeButton.showsMenuAsPrimaryAction = true
        stackView.addArrangedSubview(typeButton)

        refresh()
    }

    /// Re-derive button appearance from the page's draft (pushed in from
    /// `DocumentTitleField.updateUIView` whenever the draft changes).
    func update(_ newState: DocumentQuickState) {
        state = newState
        refresh()
    }

    private func refresh() {
        flagButton.setImage(UIImage(systemName: state.flagged ? "flag.fill" : "flag"), for: .normal)
        setActive(flagButton, state.flagged)

        priorityButton.menu = makePriorityMenu()
        setActive(priorityButton, state.priority != .none)

        typeButton.menu = makeTypeMenu()
        typeButton.setImage(UIImage(systemName: Self.typeSymbol(state.type)), for: .normal)
        setActive(typeButton, false)
        setActive(detailsButton, false)
    }

    private func makePriorityMenu() -> UIMenu {
        let options: [(String, Item.Priority)] = [
            ("None", .none), ("Low", .low), ("Medium", .medium), ("High", .high)
        ]
        let actions = options.map { (title, priority) in
            UIAction(
                title: title,
                state: priority == state.priority ? .on : .off
            ) { [weak self] _ in
                self?.onSetPriority(priority)
            }
        }
        return UIMenu(title: "Priority", children: actions)
    }

    private func makeTypeMenu() -> UIMenu {
        let options: [(String, String, Item.ItemType)] = [
            ("Task", "circle", .task),
            ("Note", "text.document", .note),
            ("Event", "calendar", .event)
        ]
        let actions = options.map { (title, symbol, type) in
            UIAction(
                title: title,
                image: UIImage(systemName: symbol),
                state: type == state.type ? .on : .off
            ) { [weak self] _ in
                self?.onSetType(type)
            }
        }
        return UIMenu(title: "Type", children: actions)
    }

    private static func typeSymbol(_ type: Item.ItemType) -> String {
        switch type {
        case .task:  return "circle"
        case .note:  return "text.document"
        case .event: return "calendar"
        case .habit: return "checkmark.arrow.trianglehead.clockwise"
        }
    }
}

// MARK: - Title field

/// The document title: a plain `UITextView` styled like the old SwiftUI
/// TextField (title2 semibold, wraps, self-sizing) so it can carry the quick
/// details bar as its keyboard accessory. Return hops into the body editor.
private struct DocumentTitleField: UIViewRepresentable {
    @Binding var text: String
    var textColor: UIColor
    var quickState: DocumentQuickState
    var onToggleFlag: () -> Void
    var onSetPriority: (Item.Priority) -> Void
    var onSetType: (Item.ItemType) -> Void
    var onOpenDetails: () -> Void
    let bridge: DocumentFocusBridge

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, bridge: bridge) }

    func makeUIView(context: Context) -> PlaceholderTextView {
        let tv = PlaceholderTextView()
        let font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 22, weight: .semibold))
        tv.configureAsInlineField(font: font, textColor: textColor, placeholder: "Title")
        tv.text = text
        tv.delegate = context.coordinator
        tv.inputAccessoryView = context.coordinator.quickBar
        tv.returnKeyType = .next
        tv.tintColor = UIColor(ListsTokens.accent)
        tv.adjustsFontForContentSizeCategory = true
        tv.accessibilityIdentifier = "document.title"
        bridge.titleView = tv
        return tv
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = textColor
        let bar = context.coordinator.quickBar
        bar.onToggleFlag = onToggleFlag
        bar.onSetPriority = onSetPriority
        bar.onSetType = onSetType
        bar.onOpenDetails = onOpenDetails
        bar.update(quickState)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PlaceholderTextView, context: Context) -> CGSize? {
        // Width-stable measurement — see InlineTextField for the "phantom
        // extra line" this prevents.
        let proposed = proposal.width ?? 0
        let width: CGFloat
        if proposed > 1 {
            width = proposed
            uiView.lastMeasuredWidth = proposed
        } else if uiView.lastMeasuredWidth > 1 {
            width = uiView.lastMeasuredWidth
        } else {
            return nil
        }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        private let bridge: DocumentFocusBridge
        let quickBar = DocumentQuickDetailsBar.make()

        init(text: Binding<String>, bridge: DocumentFocusBridge) {
            self.text = text
            self.bridge = bridge
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText replacement: String) -> Bool {
            // Return in the title hops into the body instead of a newline.
            if replacement == "\n" {
                bridge.focusBody()
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            (textView as? PlaceholderTextView)?.refreshPlaceholder()
            text.wrappedValue = textView.text
        }
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
    var bridge: DocumentFocusBridge? = nil
    /// Generous floor so an empty body still reads as "tap here and type".
    var minHeight: CGFloat = 220
    /// Body text sits at the page's left margin (Apple Notes-style), flush left
    /// rather than indented to line up with the title — a small inset so glyphs
    /// don't hug the edge.
    var leadingInset: CGFloat = 5

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
        bridge?.bodyView = textView

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
