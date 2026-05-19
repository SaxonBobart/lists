import Foundation

/// First-launch seed data — created once when no Lists folder exists on disk.
/// Provides a few user lists and a varied set of items so that every
/// sidebar surface (Today, Scheduled, Flagged, Urgent, Completed, Tags,
/// individual lists) has something to show.
public enum SampleData {

    /// User lists seeded alongside the Inbox. Inbox keeps its built-in
    /// id; these get plain string ids so they're easy to recognize on disk.
    ///
    /// Order matters: any list with a `parentId` must appear *after* its
    /// parent so `FileStore.writeList` can resolve the parent's on-disk URL
    /// when seeding.
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
                position: 1
            ),
            ItemList(
                id: "personal",
                name: "Personal",
                icon: "person.fill",
                color: .purple,
                defaultItemType: .task,
                createdAt: now,
                modifiedAt: now,
                position: 2
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
                id: "trip-planning",
                name: "Trip planning",
                icon: "airplane",
                color: .teal,
                defaultItemType: .task,
                createdAt: now,
                modifiedAt: now,
                position: 4
            ),
            ItemList(
                id: "trip-packing",
                name: "Packing",
                icon: "suitcase.fill",
                color: .indigo,
                defaultItemType: .task,
                createdAt: now,
                modifiedAt: now,
                position: 1,
                parentId: "trip-planning"
            ),
            ItemList(
                id: "trip-bookings",
                name: "Bookings",
                icon: "ticket.fill",
                color: .pink,
                defaultItemType: .task,
                createdAt: now,
                modifiedAt: now,
                position: 2,
                parentId: "trip-planning"
            )
        ]
    }

    /// Seed items spread across Inbox, Work, Personal, and Groceries.
    /// Designed so every smart-list and the Tags screen have content.
    public static func seedItems(
        inboxId: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Item] {
        let today9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let today14 = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now) ?? now
        let today18 = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        let yesterday19 = calendar.date(
            byAdding: .day, value: -1,
            to: calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
        ) ?? now
        let twoDaysAgo = calendar.date(
            byAdding: .day, value: -2,
            to: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        ) ?? now
        let tomorrow14 = calendar.date(
            byAdding: .day, value: 1,
            to: calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now) ?? now
        ) ?? now
        let inThreeDays = calendar.date(
            byAdding: .day, value: 3,
            to: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
        ) ?? now
        let nextWeek = calendar.date(
            byAdding: .day, value: 7,
            to: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: now) ?? now
        ) ?? now

        // Parents are referenced by sub-items so we hold them as `let`.
        let trip = Item(
            type: .task,
            title: "Plan trip to Tasmania",
            body: "Cradle Mountain + Hobart over the long weekend.\n",
            listId: inboxId,
            tags: ["travel"],
            due: tomorrow14
        )

        var items: [Item] = []

        // ── Inbox ─────────────────────────────────────────────────────
        items += [
            Item(
                type: .task,
                title: "Pay phone bill",
                body: "Due before close of business.\n",
                listId: inboxId,
                tags: ["finance"],
                done: false,
                due: yesterday19,
                priority: .medium,
                flagged: true
            ),
            Item(
                type: .task,
                title: "Stand-up at 9am",
                body: "Quick check-in with the team.\n",
                listId: inboxId,
                due: today9
            ),
            Item(
                type: .task,
                title: "Pick up dry cleaning",
                listId: inboxId,
                due: today18
            ),
            trip,
            Item(
                type: .task,
                title: "Book accommodation",
                listId: inboxId,
                parentId: trip.id,
                tags: ["travel"],
                due: tomorrow14
            ),
            Item(
                type: .task,
                title: "Pack hiking boots",
                listId: inboxId,
                parentId: trip.id,
                tags: ["travel"]
            )
        ]

        // ── Work ──────────────────────────────────────────────────────
        items += [
            Item(
                type: .task,
                title: "Review Q3 report",
                body: "Sign-off needed before the board meeting.\n",
                listId: "work",
                tags: ["work", "finance"],
                due: today14,
                priority: .high,
                flagged: true,
                triggers: Triggers(urgent: TriggerToggle(enabled: true))
            ),
            Item(
                type: .task,
                title: "Email Sarah about onboarding",
                listId: "work",
                tags: ["work"],
                due: today9
            ),
            Item(
                type: .task,
                title: "Prep slides for Friday",
                listId: "work",
                tags: ["work"],
                due: inThreeDays
            ),
            Item(
                type: .task,
                title: "Submit timesheet",
                listId: "work",
                tags: ["work", "admin"],
                done: true,
                completedAt: yesterday19,
                due: yesterday19
            ),
            Item(
                type: .note,
                title: "1:1 notes",
                body: "What I want to bring up next week:\n- promotion timeline\n- team headcount\n",
                listId: "work",
                tags: ["work"]
            )
        ]

        // ── Personal ──────────────────────────────────────────────────
        items += [
            Item(
                type: .task,
                title: "Call Mum",
                listId: "personal",
                tags: ["family"],
                due: today18,
                flagged: true
            ),
            Item(
                type: .task,
                title: "Book dentist appointment",
                listId: "personal",
                tags: ["health", "admin"],
                due: nextWeek
            ),
            Item(
                type: .habit,
                title: "Read 30 minutes",
                body: "Wind-down routine before bed.\n",
                listId: "personal",
                tags: ["health"],
                frequency: .daily,
                goalPerCycle: 1
            ),
            Item(
                type: .task,
                title: "Renew passport",
                listId: "personal",
                tags: ["admin"],
                due: twoDaysAgo,
                flagged: true
            ),
            Item(
                type: .task,
                title: "Birthday gift for Alex",
                listId: "personal",
                tags: ["family"],
                due: nextWeek
            )
        ]

        // ── Trip planning (parent list with its own items) ────────────
        items += [
            Item(
                type: .task,
                title: "Confirm visa",
                listId: "trip-planning",
                tags: ["travel"],
                due: inThreeDays
            ),
            Item(
                type: .task,
                title: "Tell neighbour about plants",
                listId: "trip-planning",
                tags: ["travel"]
            )
        ]

        // ── Packing (child of trip-planning) ──────────────────────────
        items += [
            Item(
                type: .task,
                title: "Hiking boots",
                listId: "trip-packing",
                tags: ["travel"]
            ),
            Item(
                type: .task,
                title: "Passport",
                listId: "trip-packing",
                tags: ["travel"]
            ),
            Item(
                type: .task,
                title: "Rain jacket",
                listId: "trip-packing",
                tags: ["travel"]
            )
        ]

        // ── Bookings (child of trip-planning) ─────────────────────────
        items += [
            Item(
                type: .task,
                title: "Hotel reservation",
                listId: "trip-bookings",
                tags: ["travel"],
                due: tomorrow14
            ),
            Item(
                type: .task,
                title: "Rental car",
                listId: "trip-bookings",
                tags: ["travel"]
            )
        ]

        // ── Groceries ─────────────────────────────────────────────────
        items += [
            Item(
                type: .task,
                title: "Milk",
                listId: "groceries",
                tags: ["food"],
                due: today18,
                dueAllDay: true
            ),
            Item(
                type: .task,
                title: "Sourdough bread",
                listId: "groceries",
                tags: ["food"],
                due: today18,
                dueAllDay: true
            ),
            Item(
                type: .task,
                title: "Avocados",
                listId: "groceries",
                tags: ["food"],
                due: today18,
                dueAllDay: true
            ),
            Item(
                type: .task,
                title: "Coffee beans",
                listId: "groceries",
                tags: ["food"],
                due: today18,
                dueAllDay: true
            ),
            Item(
                type: .task,
                title: "Eggs",
                listId: "groceries",
                tags: ["food"],
                done: true,
                completedAt: yesterday19,
                dueAllDay: true
            )
        ]

        return items
    }
}
