import Foundation

/// First-launch seed data — created once when no Lists folder exists on disk.
///
/// This seed is intentionally minimal: each list demonstrates a different
/// nesting shape so every feature surface (sections, sub-lists, nested
/// items, habit, completed-lingering) has visible content out of the box.
public enum SampleData {

    // Stable section ids so seeded items can reference them.
    private static let healthSectionId = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    private static let adminSectionId  = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!

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
                position: 2,
                sections: [
                    ListSection(id: healthSectionId, name: "Health", position: 1),
                    ListSection(id: adminSectionId,  name: "Admin",  position: 2)
                ]
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
                position: 3
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

    /// Seed items spread across Inbox, Work, Personal (with sections),
    /// and the 3-level Projects tree. Designed to show every nesting type.
    public static func seedItems(
        inboxId: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Item] {
        let today9      = calendar.date(bySettingHour: 9,  minute: 0, second: 0, of: now) ?? now
        let today18     = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        let yesterday19 = calendar.date(
            byAdding: .day, value: -1,
            to: calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
        ) ?? now
        let tomorrow14 = calendar.date(
            byAdding: .day, value: 1,
            to: calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now) ?? now
        ) ?? now

        var items: [Item] = []

        // ── Inbox: one quick task ─────────────────────────────────────
        items.append(
            Item(
                type: .task,
                title: "Pay phone bill",
                listId: inboxId,
                tags: ["finance"],
                due: yesterday19,
                flagged: true
            )
        )

        // ── Work: flat list with a nested parent/child item ───────────
        let emailSarah = Item(
            type: .task,
            title: "Email Sarah about onboarding",
            listId: "work",
            tags: ["work"],
            due: today9
        )
        items.append(emailSarah)
        items.append(
            Item(
                type: .task,
                title: "Draft reply",
                listId: "work",
                parentId: emailSarah.id,
                tags: ["work"]
            )
        )
        items.append(
            Item(
                type: .task,
                title: "Submit timesheet",
                listId: "work",
                tags: ["work", "admin"],
                done: true,
                completedAt: yesterday19,
                due: yesterday19
            )
        )

        // ── Personal: 2 sections + Others, with nested items ──────────
        // Health section
        let run5km = Item(
            type: .task,
            title: "Run 5km",
            listId: "personal",
            section: healthSectionId.uuidString,
            tags: ["health"],
            due: today18
        )
        items.append(run5km)
        items.append(
            Item(
                type: .task,
                title: "Stretch first",
                listId: "personal",
                section: healthSectionId.uuidString,
                parentId: run5km.id,
                tags: ["health"]
            )
        )
        items.append(
            Item(
                type: .habit,
                title: "Read 30 minutes",
                body: "Wind-down routine before bed.\n",
                listId: "personal",
                section: healthSectionId.uuidString,
                tags: ["health"],
                frequency: .daily,
                goalPerCycle: 1
            )
        )

        // Admin section
        let bookDentist = Item(
            type: .task,
            title: "Book dentist appointment",
            listId: "personal",
            section: adminSectionId.uuidString,
            tags: ["health", "admin"]
        )
        items.append(bookDentist)
        items.append(
            Item(
                type: .task,
                title: "Confirm preferred time",
                listId: "personal",
                section: adminSectionId.uuidString,
                parentId: bookDentist.id,
                tags: ["admin"]
            )
        )
        items.append(
            Item(
                type: .task,
                title: "Renew passport",
                listId: "personal",
                section: adminSectionId.uuidString,
                tags: ["admin"],
                flagged: true
            )
        )

        // Others (no section assigned) — items still visible in Personal
        items.append(
            Item(
                type: .task,
                title: "Call Mum",
                listId: "personal",
                tags: ["family"],
                due: today18
            )
        )
        items.append(
            Item(
                type: .task,
                title: "Birthday gift for Alex",
                listId: "personal",
                tags: ["family"]
            )
        )

        // ── Projects tree: items at each level of list nesting ────────
        items.append(
            Item(
                type: .note,
                title: "Roadmap ideas",
                body: "Rough sketch of upcoming projects.\n",
                listId: "projects"
            )
        )
        items.append(
            Item(
                type: .task,
                title: "Design schema",
                listId: "projects-sideapp",
                tags: ["work"]
            )
        )
        let buildSync = Item(
            type: .task,
            title: "Build sync",
            listId: "projects-sideapp-sprint1",
            tags: ["work"],
            due: tomorrow14
        )
        items.append(buildSync)
        items.append(
            Item(
                type: .task,
                title: "Test sync end-to-end",
                listId: "projects-sideapp-sprint1",
                parentId: buildSync.id,
                tags: ["work"]
            )
        )
        items.append(
            Item(
                type: .task,
                title: "Build editor",
                listId: "projects-sideapp-sprint1",
                tags: ["work"]
            )
        )

        return items
    }
}
