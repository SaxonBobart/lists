import Foundation
import UIKit

/// First-launch seed data, created once when no Lists folder exists on disk.
///
/// This is a neutral rendering fixture rather than a pretend personal setup.
/// A fresh app should show the app's current surfaces clearly: list nesting,
/// sections, item types, completion states, dates, metadata chips, and Markdown
/// rendering.
public enum SampleData {
    /// Local, previewable files for the explicit sample-library loader and isolated UI checks.
    @MainActor
    static func prepareAttachmentSamples(at root: URL) async throws {
        let files = FileStore(root: root)
        try await files.ensureRoot()
        let loaded = try await files.loadAll()
        guard !loaded.lists.contains(where: { $0.list.id == "attachment-samples" }) else { return }
        let list = ItemList(id: "attachment-samples", name: "Attachment samples", icon: "paperclip", color: .blue,
                            createdAt: .now, modifiedAt: .now, position: 4)
        try await files.writeList(list)
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 594)).pdfData { context in
            context.beginPage()
            ("Sample project brief" as NSString).draw(at: CGPoint(x: 32, y: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 26, weight: .bold)])
            ("A real local PDF used for attachment validation." as NSString).draw(at: CGPoint(x: 32, y: 92), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        let png = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 300)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 480, height: 300))
            ("Concept drawing" as NSString).draw(at: CGPoint(x: 36, y: 116), withAttributes: [.font: UIFont.systemFont(ofSize: 32, weight: .semibold), .foregroundColor: UIColor.white])
        }.pngData()!
        let brief = try await files.importAttachment(data: pdf, originalFileName: "Project brief.pdf")
        let drawing = try await files.importAttachment(data: png, originalFileName: "Concept drawing.png")
        let parent = Item(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!, type: .note,
                          title: "Project notes", body: "Brief, drawings, and next steps. Use the paperclip to browse attachments; the chevron controls child notes.\n\n[Project brief](../\(brief.relativePath))\n\n[Concept drawing](../\(drawing.relativePath))", listId: list.id)
        try await files.writeItem(parent)
        try await files.writeItem(Item(type: .note, title: "Meeting notes", body: "Decisions and follow-up ideas.", listId: list.id, parentId: parent.id, sortIndex: 0))
        try await files.writeItem(Item(type: .task, title: "Send the brief", listId: list.id, parentId: parent.id, sortIndex: 1))
        let inputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Lists-SampleInputs-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: inputDirectory) }
        let source = inputDirectory.appendingPathComponent("Unlinked budget.pdf")
        try pdf.write(to: source)
        let destination = ItemList(id: "attachment-file-moves", name: "File moves", icon: "arrow.left.arrow.right", color: .indigo,
                                   createdAt: .now, modifiedAt: .now, position: 5)
        try await files.writeList(destination)
        // Exercise the same real move implementation used by collection actions.
        let imported = try await files.importStandaloneFile(fileURL: source, into: destination.id)
        _ = try await files.moveStandaloneFile(imported, to: list.id, sortIndex: 1)
        try await files.writeItem(Item(type: .note, title: "Reference note", body: "A full-screen attachment browser without sub-items.\n\n[Project brief](../\(brief.relativePath))",
                                       listId: list.id, sortIndex: 2))
        try await files.writeItem(Item(type: .task, title: "Review the budget", listId: list.id, sortIndex: 3))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--note-property-sample-data") {
            // Boundary siblings make nesting and type-specific alignment visible
            // together in the opt-in isolated UI fixture, without touching Lists/.
            try await files.writeItem(Item(type: .task, title: "Prepare the brief", listId: list.id, sortIndex: -1))
            let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(14 * 3600)
            try await files.writeItem(Item(type: .event, title: "Project review", listId: list.id,
                                           due: start, dueAllDay: false,
                                           end: start.addingTimeInterval(3600), sortIndex: 4))
        }
        if ProcessInfo.processInfo.arguments.contains("--collection-navigation-sample-data") || ProcessInfo.processInfo.arguments.contains("--document-first-sample-data") {
            for (position, id, name) in [(0, "sample-project", "Project workspace"),
                                         (1, "sample-empty", "Empty collection"),
                                         (2, "sample-research", "Research and references") ] {
                try await files.writeList(ItemList(id: id, name: name, icon: "folder", color: .blue,
                                                   createdAt: .now, modifiedAt: .now,
                                                   position: Double(position), parentId: list.id))
            }
            try await files.writeList(ItemList(id: "sample-deep", name: "Planning", icon: "folder", color: .indigo,
                                               createdAt: .now, modifiedAt: .now, position: 0, parentId: "sample-project"))
            try await files.writeItem(Item(type: .note, title: "Workspace overview", body: "A nested collection with undated notes.", listId: "sample-project"))
        }
        if ProcessInfo.processInfo.arguments.contains("--document-first-sample-data") {
            try await files.writeItem(Item(id: UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!, type: .note,
                                          title: "Blank note", body: "", listId: list.id, sortIndex: -3))
            var populated = Item(id: UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!, type: .note,
                                 title: "A few useful properties", body: "Only the properties I use belong here.\n\nThe rest of this page is for writing.", listId: list.id, sortIndex: -2)
            populated.flagged = true
            populated.priority = .high
            populated.tags = ["project"]
            try await files.writeItem(populated)
            var board = list
            board.sections = [ListSection(name: "Planning", position: 0)]
            try await files.writeList(board)
        }
        #endif
        let movedSource = inputDirectory.appendingPathComponent("Moved drawing.png")
        try png.write(to: movedSource)
        let movingDrawing = try await files.importStandaloneFile(fileURL: movedSource, into: list.id)
        _ = try await files.moveStandaloneFile(movingDrawing, to: destination.id, sortIndex: 1)
        try await files.writeItem(Item(type: .note, title: "A file moved here", body: "Moved drawing.png started in Attachment samples and now lives in this collection.", listId: destination.id, sortIndex: 0))
    }

    public static let listDemoId = "rendering-demo"
    public static let columnsDemoId = "columns-demo"
    public static let calendarDemoId = "calendar-demo"

    @MainActor
    static func applyPresentationDefaults(to preferences: ListViewPreferences) {
        preferences.setViewMode(.list, for: listDemoId)
        preferences.setViewMode(.columns, for: columnsDemoId)
        preferences.setViewMode(.calendar, for: calendarDemoId)
    }

    // MARK: - Stable section ids

    private static let tasksSection = UUID(uuidString: "11111111-0000-0000-0000-000000000101")!
    private static let notesSection = UUID(uuidString: "11111111-0000-0000-0000-000000000102")!
    private static let eventsSection = UUID(uuidString: "11111111-0000-0000-0000-000000000103")!
    private static let recurrenceSection = UUID(uuidString: "11111111-0000-0000-0000-000000000104")!
    private static let columnsTodoSection = UUID(uuidString: "22222222-0000-0000-0000-000000000201")!
    private static let columnsDoingSection = UUID(uuidString: "22222222-0000-0000-0000-000000000202")!
    private static let columnsDoneSection = UUID(uuidString: "22222222-0000-0000-0000-000000000203")!

    /// User lists seeded alongside the Inbox. Child lists appear after their
    /// parent so the file store can resolve each on-disk parent folder.
    public static func seedLists(now: Date = .now) -> [ItemList] {
        [
            ItemList(
                id: listDemoId,
                name: "List Demo",
                icon: "text.document.fill",
                color: .sage,
                createdAt: now,
                modifiedAt: now,
                position: 1,
                sections: [
                    ListSection(id: tasksSection, name: "Tasks", position: 1),
                    ListSection(id: recurrenceSection, name: "Recurrence", position: 2),
                    ListSection(id: notesSection, name: "Notes", position: 3),
                    ListSection(id: eventsSection, name: "Events", position: 4)
                ]
            ),
            ItemList(
                id: "rendering-demo-markdown",
                name: "Markdown",
                icon: "textformat",
                color: .blue,
                createdAt: now,
                modifiedAt: now,
                position: 1,
                parentId: listDemoId
            ),
            ItemList(
                id: "rendering-demo-nested",
                name: "Nested Items",
                icon: "list.bullet.indent",
                color: .indigo,
                createdAt: now,
                modifiedAt: now,
                position: 2,
                parentId: listDemoId
            ),
            ItemList(
                id: columnsDemoId,
                name: "Columns Demo",
                icon: "rectangle.split.3x1.fill",
                color: .orange,
                createdAt: now,
                modifiedAt: now,
                position: 2,
                sections: [
                    ListSection(id: columnsTodoSection, name: "To Do", position: 1),
                    ListSection(id: columnsDoingSection, name: "Doing", position: 2),
                    ListSection(id: columnsDoneSection, name: "Done", position: 3)
                ]
            ),
            ItemList(
                id: calendarDemoId,
                name: "Calendar Demo",
                icon: "calendar",
                color: .pink,
                createdAt: now,
                modifiedAt: now,
                position: 3
            )
        ]
    }

    /// Seed items cover the rendering states a designer or agent needs to see
    /// quickly. Dates are relative to `now` so smart lists stay populated.
    public static func seedItems(
        inboxId: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Item] {
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: now) ?? now
        }

        func at(_ date: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        let todayMorning = at(now, 9)
        let todayAfternoon = at(now, 15)
        let tomorrowMorning = at(day(1), 10)
        let yesterdayAfternoon = at(day(-1), 16)

        var items: [Item] = []

        items.append(Item(
            type: .task,
            title: "Inbox task with alarm and flag",
            listId: inboxId,
            tags: ["inbox", "alarm"],
            due: todayMorning,
            priority: .high,
            flagged: true,
            reminder: Reminder(enabled: true, early: EarlyReminder(value: 30, unit: .minute)),
            triggers: Triggers(alarm: TriggerToggle(enabled: true))
        ))

        items.append(Item(
            type: .task,
            title: "Overdue task",
            listId: "rendering-demo",
            section: tasksSection.uuidString,
            tags: ["overdue"],
            due: yesterdayAfternoon,
            priority: .high,
            reminder: Reminder(enabled: true)
        ))

        items.append(Item(
            type: .task,
            title: "Completed task",
            listId: "rendering-demo",
            section: tasksSection.uuidString,
            tags: ["completed"],
            done: true,
            completedAt: yesterdayAfternoon
        ))

        items.append(Item(
            type: .task,
            title: "Daily planning",
            body: "Open this item and choose Completion History to review or correct past occurrences.",
            listId: "rendering-demo",
            section: recurrenceSection.uuidString,
            tags: ["recurrence", "history"],
            due: todayMorning,
            recurrence: Recurrence(rrule: "FREQ=DAILY"),
            recurrenceOccurrences: [
                RecurrenceOccurrence(
                    scheduledAt: at(day(-2), 9),
                    status: .completed,
                    completedAt: at(day(-2), 9, 18)
                ),
                RecurrenceOccurrence(
                    scheduledAt: at(day(-1), 9),
                    status: .missed
                ),
                RecurrenceOccurrence(
                    scheduledAt: todayMorning,
                    status: .open
                )
            ]
        ))

        let weeklyReviewStart = at(day(1), 14)
        items.append(Item(
            type: .event,
            title: "Weekly review",
            body: "A completable recurring event with two genuine completions.",
            listId: "rendering-demo",
            section: recurrenceSection.uuidString,
            tags: ["recurrence", "event"],
            due: weeklyReviewStart,
            end: weeklyReviewStart.addingTimeInterval(30 * 60),
            completable: true,
            recurrence: Recurrence(rrule: "FREQ=WEEKLY"),
            recurrenceOccurrences: [
                RecurrenceOccurrence(
                    scheduledAt: at(day(-13), 14),
                    status: .completed,
                    completedAt: at(day(-13), 14, 24)
                ),
                RecurrenceOccurrence(
                    scheduledAt: at(day(-6), 14),
                    status: .completed,
                    completedAt: at(day(-6), 14, 11)
                ),
                RecurrenceOccurrence(
                    scheduledAt: weeklyReviewStart,
                    status: .open
                )
            ]
        ))

        let parentTask = Item(
            type: .task,
            title: "Parent task with subtasks",
            listId: "rendering-demo",
            section: tasksSection.uuidString,
            tags: ["hierarchy"],
            due: tomorrowMorning,
            priority: .medium
        )
        items.append(parentTask)
        items.append(Item(
            type: .task,
            title: "First subtask",
            listId: "rendering-demo",
            section: tasksSection.uuidString,
            parentId: parentTask.id,
            tags: ["hierarchy"]
        ))
        items.append(Item(
            type: .task,
            title: "Completed subtask",
            listId: "rendering-demo",
            section: tasksSection.uuidString,
            parentId: parentTask.id,
            tags: ["hierarchy"],
            done: true,
            completedAt: yesterdayAfternoon
        ))

        items.append(Item(
            type: .note,
            title: "Markdown rendering note",
            body: markdownRenderingBody,
            listId: "rendering-demo",
            section: notesSection.uuidString,
            tags: ["markdown", "preview"]
        ))

        items.append(Item(
            type: .note,
            title: "Callout rendering note",
            body: calloutRenderingBody,
            listId: "rendering-demo",
            section: notesSection.uuidString,
            tags: ["markdown", "callouts"]
        ))

        items.append(Item(
            type: .note,
            title: "Short note preview",
            body: "Plain note body with **bold**, *italic*, `inline code`, and ==highlight==.",
            listId: "rendering-demo",
            section: notesSection.uuidString,
            tags: ["note"]
        ))

        items.append(Item(
            type: .event,
            title: "Timed event",
            listId: "rendering-demo",
            section: eventsSection.uuidString,
            tags: ["event"],
            due: todayAfternoon,
            end: at(now, 16),
            reminder: Reminder(enabled: true, early: EarlyReminder(value: 10, unit: .minute))
        ))

        items.append(Item(
            type: .event,
            title: "All-day multi-day event",
            body: "All-day event body for document rendering.",
            listId: "rendering-demo",
            section: eventsSection.uuidString,
            tags: ["event", "all-day"],
            due: at(day(2), 9),
            dueAllDay: true,
            end: at(day(4), 17)
        ))

        items.append(Item(
            type: .event,
            title: "Completable event",
            listId: "rendering-demo",
            section: eventsSection.uuidString,
            tags: ["event", "tasklike"],
            due: at(day(1), 14),
            end: at(day(1), 14, 30),
            completable: true
        ))





        items.append(Item(
            type: .task,
            title: "Plan the next release",
            listId: columnsDemoId,
            section: columnsTodoSection.uuidString,
            tags: ["board"],
            priority: .high
        ))

        items.append(Item(
            type: .task,
            title: "Polish the onboarding copy",
            listId: columnsDemoId,
            section: columnsDoingSection.uuidString,
            tags: ["board"],
            due: tomorrowMorning
        ))

        items.append(Item(
            type: .note,
            title: "Release notes",
            body: "A note can sit in a column alongside tasks.",
            listId: columnsDemoId,
            section: columnsDoingSection.uuidString,
            tags: ["board", "note"]
        ))

        items.append(Item(
            type: .task,
            title: "Review the current build",
            listId: columnsDemoId,
            section: columnsDoneSection.uuidString,
            tags: ["board"],
            done: true,
            completedAt: yesterdayAfternoon
        ))

        items.append(Item(
            type: .event,
            title: "Morning planning",
            listId: calendarDemoId,
            tags: ["calendar"],
            due: todayMorning,
            end: at(now, 9, 30)
        ))

        items.append(Item(
            type: .event,
            title: "Design review",
            listId: calendarDemoId,
            tags: ["calendar"],
            due: tomorrowMorning,
            end: at(day(1), 11)
        ))

        items.append(Item(
            type: .task,
            title: "Prepare review notes",
            listId: calendarDemoId,
            tags: ["calendar", "task"],
            due: at(day(2), 9)
        ))

        items.append(Item(
            type: .event,
            title: "Launch window",
            listId: calendarDemoId,
            tags: ["calendar", "all-day"],
            due: at(day(3), 9),
            dueAllDay: true,
            end: at(day(4), 17)
        ))

        items.append(Item(
            type: .note,
            title: "Markdown child-list note",
            body: """
            # Child list note

            This item lives inside a nested list.

            - Nested list row
            - Document body row
            - Breadcrumb row
            """,
            listId: "rendering-demo-markdown",
            tags: ["nested", "markdown"]
        ))

        let nestedParent = Item(
            type: .task,
            title: "Nested list parent task",
            listId: "rendering-demo-nested",
            tags: ["nested"],
            priority: .low
        )
        items.append(nestedParent)
        items.append(Item(
            type: .task,
            title: "Nested list child task",
            listId: "rendering-demo-nested",
            parentId: nestedParent.id,
            tags: ["nested"]
        ))

        return items
    }

    private static let markdownRenderingBody = """
    # Heading 1
    ## Heading 2
    ### Heading 3

    Body text with **bold**, *italic*, ~~strikethrough~~, `inline code`, and ==highlight==.

    > Quote block for preview rendering.

    > [!NOTE]
    > GitHub-style callouts stay portable blockquotes.

    [Lists link card](https://example.com/lists)

    - Bulleted row
    - Another bullet

    1. Numbered row
    2. Another numbered row

    - [ ] Checklist item
    - [x] Completed checklist item

    | Column 1 | Column 2 |
    | --- | --- |
    | Cell A | Cell B |

    Inline math: $x + y = z$

    $$
    a^2 + b^2 = c^2
    $$

    ```mermaid
    graph TD
        A[Start] --> B[Next]
    ```
    """

    private static let calloutRenderingBody = """
    # Callout rendering

    > A plain quote should read as one connected block, not separate broken lines.
    > It can wrap across lines while keeping one continuous rail.

    > [!NOTE]
    > Highlights information that is useful while skimming.

    > [!TIP]
    > Optional guidance that helps the reader be more successful.

    > [!IMPORTANT]
    > Key information that changes how the reader should proceed.

    > [!WARNING]
    > Urgent content that needs attention before continuing.

    > [!CAUTION]
    > Negative consequences or destructive actions.

    > [!TIP] Nested callouts
    > Parent callout body text.
    > > [!NOTE]
    > > A nested note should sit inside the parent with its own rail.
    > > > [!IMPORTANT]
    > > > A third level should still remain readable.
    > Back to the parent callout.
    """




}
