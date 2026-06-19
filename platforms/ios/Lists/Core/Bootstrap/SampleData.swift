import Foundation

/// First-launch seed data — created once when no Lists folder exists on disk.
///
/// The seed is a guided tour of the whole app: every list shape (sections,
/// 3-level nesting, a shopping list), every item type (task / habit / note /
/// event), and every control surface that has shipped — priorities, flags,
/// reminders with early offsets, recurrence, urgent triggers, all-day and
/// timed events with timezones, habits with months of real completion history
/// (so streaks, the heatmap, flexible weekly goals and multi-count days all
/// render with live data), and markdown notes. It exists so a fresh install,
/// and every design screenshot, shows the product full rather than empty.
public enum SampleData {

    // MARK: - Stable section ids (so seeded items can reference their section)
    private static let workPrioritiesSection = UUID(uuidString: "11111111-0000-0000-0000-000000000010")!
    private static let workMeetingsSection   = UUID(uuidString: "11111111-0000-0000-0000-000000000011")!
    private static let workBacklogSection    = UUID(uuidString: "11111111-0000-0000-0000-000000000012")!
    private static let healthSection         = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    private static let adminSection          = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!

    /// User lists seeded alongside the Inbox. Any list with a `parentId`
    /// must appear *after* its parent so `FileStore.writeList` can resolve
    /// the parent's on-disk URL when seeding.
    public static func seedLists(now: Date = .now) -> [ItemList] {
        [
            ItemList(
                id: "work",
                name: "Work",
                icon: "briefcase.fill",
                color: .orange,
                defaultItemType: .task,
                createdAt: now,
                modifiedAt: now,
                position: 1,
                sections: [
                    ListSection(id: workPrioritiesSection, name: "Priorities", position: 1),
                    ListSection(id: workMeetingsSection,   name: "Meetings",   position: 2),
                    ListSection(id: workBacklogSection,    name: "Backlog",    position: 3)
                ]
            ),
            ItemList(
                id: "personal",
                name: "Personal",
                icon: "person.fill",
                color: .purple,
                defaultItemType: .task,
                createdAt: now,
                modifiedAt: now,
                position: 2,
                sections: [
                    ListSection(id: healthSection, name: "Health", position: 1),
                    ListSection(id: adminSection,  name: "Admin",  position: 2)
                ]
            ),
            ItemList(
                id: "groceries",
                name: "Groceries",
                icon: "cart.fill",
                color: .green,
                defaultItemType: .task,
                groceryMode: true,
                createdAt: now,
                modifiedAt: now,
                position: 3
            ),
            ItemList(
                id: "travel",
                name: "Travel",
                icon: "airplane",
                color: .blue,
                defaultItemType: .event,
                createdAt: now,
                modifiedAt: now,
                position: 4
            ),
            // 3-level list nesting: Projects → Side App → Sprint 1
            ItemList(
                id: "projects",
                name: "Projects",
                icon: "folder.fill",
                color: .indigo,
                defaultItemType: .task,
                createdAt: now,
                modifiedAt: now,
                position: 5
            ),
            ItemList(
                id: "projects-sideapp",
                name: "Side App",
                icon: "hammer.fill",
                color: .teal,
                defaultItemType: .task,
                createdAt: now,
                modifiedAt: now,
                position: 1,
                parentId: "projects"
            ),
            ItemList(
                id: "projects-sideapp-sprint1",
                name: "Sprint 1",
                icon: "flag.fill",
                color: .pink,
                defaultItemType: .task,
                createdAt: now,
                modifiedAt: now,
                position: 1,
                parentId: "projects-sideapp"
            )
        ]
    }

    /// Seed items spanning every type and feature, spread across the Inbox and
    /// the lists above. Dates are computed relative to `now` so smart lists
    /// (Today / Scheduled / Flagged / Urgent / Completed) and the habit
    /// heatmap stay populated no matter when the app is first launched.
    public static func seedItems(
        inboxId: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Item] {

        // MARK: Date helpers
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: now) ?? now
        }
        func at(_ date: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        // A representative noon instant `offset` days from today.
        func noon(_ offset: Int) -> Date { at(day(offset), 12) }

        let todayMorning = at(now, 9)
        let todayEvening = at(now, 18)
        let yesterdayEve = at(day(-1), 19)

        // MARK: Habit completion builders
        // One completion per day for a run of consecutive days ending today,
        // optionally skipping a few days (to show a forgiving streak) or
        // logging several per day (to show an X-per-day counter).
        func daily(streak: Int, perDay: Int = 1, skip: Set<Int> = []) -> [HabitCompletion] {
            var out: [HabitCompletion] = []
            for d in 0..<streak where !skip.contains(d) {
                let base = noon(-d)
                for n in 0..<perDay {
                    out.append(HabitCompletion(at: base.addingTimeInterval(TimeInterval(n * 60))))
                }
            }
            return out
        }

        var items: [Item] = []

        // ── Inbox ─────────────────────────────────────────────────────────
        // Overdue + flagged + URGENT trigger + reminder: lights up Today,
        // Flagged and Urgent at once.
        items.append(Item(
            type: .task,
            title: "Pay phone bill",
            listId: inboxId,
            tags: ["finance"],
            due: yesterdayEve,
            priority: .high,
            flagged: true,
            reminder: Reminder(enabled: true),
            triggers: Triggers(urgent: TriggerToggle(enabled: true))
        ))
        items.append(Item(
            type: .task,
            title: "Reply to landlord about lease",
            listId: inboxId,
            tags: ["home"]
        ))

        // ── Work › Priorities ─────────────────────────────────────────────
        let roadmap = Item(
            type: .task,
            title: "Finish Q3 roadmap deck",
            body: "Cover hiring, infra spend, and the sync milestone.\n",
            listId: "work",
            section: workPrioritiesSection.uuidString,
            tags: ["work"],
            due: todayEvening,
            priority: .high,
            flagged: true,
            reminder: Reminder(enabled: true, early: EarlyReminder(value: 1, unit: .hour))
        )
        items.append(roadmap)
        items.append(Item(
            type: .task,
            title: "Pull metrics from dashboard",
            listId: "work",
            section: workPrioritiesSection.uuidString,
            parentId: roadmap.id,
            tags: ["work"]
        ))
        let emailSarah = Item(
            type: .task,
            title: "Email Sarah about onboarding",
            listId: "work",
            section: workPrioritiesSection.uuidString,
            tags: ["work"],
            due: todayMorning
        )
        items.append(emailSarah)
        items.append(Item(
            type: .task,
            title: "Draft reply",
            listId: "work",
            section: workPrioritiesSection.uuidString,
            parentId: emailSarah.id,
            tags: ["work"]
        ))
        // Recurring weekly task.
        items.append(Item(
            type: .task,
            title: "Submit timesheet",
            listId: "work",
            section: workPrioritiesSection.uuidString,
            tags: ["work", "admin"],
            due: todayEvening,
            recurrence: Recurrence(rrule: "FREQ=WEEKLY;BYDAY=FR")
        ))

        // ── Work › Meetings (events) ──────────────────────────────────────
        // Non-completable recurring calendar event earlier today.
        items.append(Item(
            type: .event,
            title: "Team standup",
            listId: "work",
            section: workMeetingsSection.uuidString,
            tags: ["work"],
            due: at(now, 9, 0),
            end: at(now, 9, 15),
            recurrence: Recurrence(rrule: "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR")
        ))
        // Completable event later today (behaves like a task).
        items.append(Item(
            type: .event,
            title: "1:1 with manager",
            listId: "work",
            section: workMeetingsSection.uuidString,
            tags: ["work"],
            due: at(now, 15, 0),
            end: at(now, 15, 30),
            completable: true,
            reminder: Reminder(enabled: true, early: EarlyReminder(value: 10, unit: .minute))
        ))
        // Future event (Scheduled).
        items.append(Item(
            type: .event,
            title: "Design review",
            listId: "work",
            section: workMeetingsSection.uuidString,
            tags: ["work"],
            due: at(day(3), 11, 0),
            end: at(day(3), 12, 0)
        ))

        // ── Work › Backlog ────────────────────────────────────────────────
        items.append(Item(
            type: .task,
            title: "Refactor sync layer",
            listId: "work",
            section: workBacklogSection.uuidString,
            tags: ["work"],
            priority: .medium
        ))
        // Completed task → populates the Completed smart list.
        items.append(Item(
            type: .task,
            title: "Write API docs",
            listId: "work",
            section: workBacklogSection.uuidString,
            tags: ["work"],
            done: true,
            completedAt: yesterdayEve
        ))

        // ── Personal › Health (habits + a task) ───────────────────────────
        // Strong daily streak — full heatmap, long streak count.
        items.append(Item(
            type: .habit,
            title: "Read 30 minutes",
            body: "Wind-down routine before bed.\n",
            listId: "personal",
            section: healthSection.uuidString,
            tags: ["health"],
            frequency: .daily,
            goalPerCycle: 1,
            completions: daily(streak: 47)
        ))
        // Daily habit with a couple of gaps — shows a forgiving streak.
        items.append(Item(
            type: .habit,
            title: "Meditate",
            listId: "personal",
            section: healthSection.uuidString,
            tags: ["health"],
            due: todayMorning,
            reminder: Reminder(enabled: true),
            frequency: .daily,
            goalPerCycle: 1,
            completions: daily(streak: 22, skip: [3, 4, 11])
        ))
        // Multi-count daily habit — 8 glasses, partway done today.
        items.append(Item(
            type: .habit,
            title: "Drink water",
            listId: "personal",
            section: healthSection.uuidString,
            tags: ["health"],
            frequency: .daily,
            goalPerCycle: 8,
            completions: daily(streak: 1, perDay: 5) + daily(streak: 12, perDay: 8).filter {
                // keep the earlier days full, drop today's extras (already added above)
                !calendar.isDate($0.at, inSameDayAs: now)
            }
        ))
        // Flexible weekly goal — "3 times a week", 2 logged so far this week.
        items.append(Item(
            type: .habit,
            title: "Workout",
            body: "Strength on Mon/Wed, run on Fri.\n",
            listId: "personal",
            section: healthSection.uuidString,
            tags: ["health"],
            frequency: .weekly,
            goalPerCycle: 3,
            completions: weeklyFlexible(now: now, calendar: calendar),
            flexibleGoal: true
        ))
        let run5k = Item(
            type: .task,
            title: "Run 5km",
            listId: "personal",
            section: healthSection.uuidString,
            tags: ["health"],
            due: todayEvening
        )
        items.append(run5k)
        items.append(Item(
            type: .task,
            title: "Stretch first",
            listId: "personal",
            section: healthSection.uuidString,
            parentId: run5k.id,
            tags: ["health"]
        ))

        // ── Personal › Admin ──────────────────────────────────────────────
        let dentist = Item(
            type: .task,
            title: "Book dentist appointment",
            listId: "personal",
            section: adminSection.uuidString,
            tags: ["health", "admin"]
        )
        items.append(dentist)
        items.append(Item(
            type: .task,
            title: "Confirm preferred time",
            listId: "personal",
            section: adminSection.uuidString,
            parentId: dentist.id,
            tags: ["admin"]
        ))
        items.append(Item(
            type: .task,
            title: "Renew passport",
            listId: "personal",
            section: adminSection.uuidString,
            tags: ["admin"],
            due: at(day(6), 12),
            dueAllDay: true,
            priority: .low,
            flagged: true
        ))

        // ── Personal (no section) ─────────────────────────────────────────
        items.append(Item(
            type: .task,
            title: "Call Mum",
            listId: "personal",
            tags: ["family"],
            due: todayEvening,
            reminder: Reminder(enabled: true)
        ))
        items.append(Item(
            type: .task,
            title: "Birthday gift for Alex",
            listId: "personal",
            tags: ["family"],
            due: at(day(3), 12),
            dueAllDay: true
        ))
        items.append(Item(
            type: .note,
            title: "Book club — June",
            body: """
            # Book club notes

            **This month:** *Project Hail Mary*

            ## Discussion
            - Favourite moment?
            - The Rocky reveal — did it land?

            ## To bring
            - [ ] Snacks
            - [x] Wine
            - [ ] Next month's pick

            > Host: Alex's place, 7pm.
            """,
            listId: "personal",
            tags: ["family"]
        ))

        // ── Groceries (shopping list) ─────────────────────────────────────
        for name in ["Milk", "Eggs", "Sourdough bread", "Avocados", "Coffee beans", "Olive oil"] {
            items.append(Item(type: .task, title: name, listId: "groceries"))
        }
        items.append(Item(
            type: .task, title: "Bananas", listId: "groceries",
            done: true, completedAt: yesterdayEve
        ))

        // ── Travel (events) ───────────────────────────────────────────────
        // Non-completable event today around midday.
        items.append(Item(
            type: .event,
            title: "Lunch with Alex",
            listId: "travel",
            tags: ["family"],
            due: at(now, 12, 0),
            end: at(now, 13, 0)
        ))
        // Timed event in another timezone.
        items.append(Item(
            type: .event,
            title: "Flight to San Francisco",
            listId: "travel",
            tags: ["travel"],
            due: at(day(5), 8, 30),
            dueTimeZone: "America/Los_Angeles",
            end: at(day(5), 11, 45),
            reminder: Reminder(enabled: true, early: EarlyReminder(value: 3, unit: .hour))
        ))
        // Multi-day, all-day event.
        items.append(Item(
            type: .event,
            title: "Design conference",
            body: "Talks at Moscone West. Badge in the wallet.\n",
            listId: "travel",
            tags: ["travel", "work"],
            due: at(day(5), 9),
            dueAllDay: true,
            end: at(day(7), 17)
        ))
        // Completable event (a calendar block you tick off).
        items.append(Item(
            type: .event,
            title: "Hotel checkout",
            listId: "travel",
            tags: ["travel"],
            due: at(day(7), 11, 0),
            end: at(day(7), 11, 30),
            completable: true
        ))

        // ── Projects tree: an item at each level of list nesting ──────────
        items.append(Item(
            type: .note,
            title: "Roadmap ideas",
            body: """
            # Roadmap ideas

            Rough sketch of where the side app could go.

            ## Near term
            - [ ] Calendar view
            - [ ] iCal import/export
            - [x] Inline editing

            ## Someday
            - Shared lists
            - Web companion
            """,
            listId: "projects"
        ))
        items.append(Item(
            type: .task,
            title: "Design schema",
            listId: "projects-sideapp",
            tags: ["work"],
            priority: .medium
        ))
        let buildSync = Item(
            type: .task,
            title: "Build sync",
            listId: "projects-sideapp-sprint1",
            tags: ["work"],
            due: at(day(1), 14, 30)
        )
        items.append(buildSync)
        items.append(Item(
            type: .task,
            title: "Test sync end-to-end",
            listId: "projects-sideapp-sprint1",
            parentId: buildSync.id,
            tags: ["work"]
        ))
        items.append(Item(
            type: .task,
            title: "Build editor",
            listId: "projects-sideapp-sprint1",
            tags: ["work"],
            priority: .medium
        ))

        return items
    }

    /// Completions for a flexible "3× a week" habit: a full 3 per week for the
    /// past several weeks, and 2 logged so far in the current week — so the
    /// detail screen reads "2 of 3 this week" with a long prior history.
    private static func weeklyFlexible(now: Date, calendar: Calendar) -> [HabitCompletion] {
        func noon(_ offset: Int) -> Date {
            let d = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d
        }
        var out: [HabitCompletion] = []
        // This week so far: two sessions (a few days back, both inside the week).
        out.append(HabitCompletion(at: noon(2)))
        out.append(HabitCompletion(at: noon(4)))
        // Prior eight weeks: three sessions each.
        for week in 1...8 {
            for within in [0, 2, 4] {
                out.append(HabitCompletion(at: noon(7 * week + within)))
            }
        }
        return out
    }
}
