import Foundation

/// First-launch seed data, created once when no Lists folder exists on disk.
///
/// This is a neutral rendering fixture rather than a pretend personal setup.
/// A fresh app should show the app's current surfaces clearly: list nesting,
/// sections, item types, completion states, dates, metadata chips, and Markdown
/// rendering.
public enum SampleData {

    // MARK: - Stable section ids

    private static let tasksSection = UUID(uuidString: "11111111-0000-0000-0000-000000000101")!
    private static let notesSection = UUID(uuidString: "11111111-0000-0000-0000-000000000102")!
    private static let eventsSection = UUID(uuidString: "11111111-0000-0000-0000-000000000103")!

    /// User lists seeded alongside the Inbox. Child lists appear after their
    /// parent so the file store can resolve each on-disk parent folder.
    public static func seedLists(now: Date = .now) -> [ItemList] {
        [
            ItemList(
                id: "rendering-demo",
                name: "Rendering Demo",
                icon: "text.document.fill",
                color: .sage,
                createdAt: now,
                modifiedAt: now,
                position: 1,
                sections: [
                    ListSection(id: tasksSection, name: "Tasks", position: 1),
                    ListSection(id: notesSection, name: "Notes", position: 2),
                    ListSection(id: eventsSection, name: "Events", position: 3)
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
                parentId: "rendering-demo"
            ),
            ItemList(
                id: "rendering-demo-nested",
                name: "Nested Items",
                icon: "list.bullet.indent",
                color: .indigo,
                createdAt: now,
                modifiedAt: now,
                position: 2,
                parentId: "rendering-demo"
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
            type: .habit,
            title: "Daily habit",
            listId: "rendering-demo",
            tags: ["habit"],
            due: todayMorning,
            reminder: Reminder(enabled: true),
            frequency: .daily,
            goalPerCycle: 1,
            completions: dailyCompletions(days: 18, now: now, calendar: calendar)
        ))

        items.append(Item(
            type: .habit,
            title: "Weekly habit goal",
            listId: "rendering-demo",
            tags: ["habit"],
            frequency: .weekly,
            goalPerCycle: 3,
            completions: weeklyCompletions(now: now, calendar: calendar),
            flexibleGoal: true
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

    private static func dailyCompletions(days: Int, now: Date, calendar: Calendar) -> [HabitCompletion] {
        (0..<days).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return HabitCompletion(at: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date)
        }
    }

    private static func weeklyCompletions(now: Date, calendar: Calendar) -> [HabitCompletion] {
        func noon(daysBack: Int) -> Date {
            let date = calendar.date(byAdding: .day, value: -daysBack, to: now) ?? now
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        }

        var completions = [HabitCompletion(at: noon(daysBack: 1)), HabitCompletion(at: noon(daysBack: 3))]
        for week in 1...5 {
            for offset in [0, 2, 4] {
                completions.append(HabitCompletion(at: noon(daysBack: week * 7 + offset)))
            }
        }
        return completions
    }
}
