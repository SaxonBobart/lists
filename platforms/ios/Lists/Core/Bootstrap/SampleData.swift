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

    // MARK: - Stable item ids
    // Tests (XCUITest + unit) address items by the dot-convention
    // `item.row.<type>.<uuid>` accessibility identifier. Pinning these UUIDs
    // here keeps tests stable across launches. Mirrored as raw strings in
    // ListsUITestsSupport.SeedId.
    public static let id_payPhoneBill        = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!
    public static let id_emailSarah          = UUID(uuidString: "22222222-0000-0000-0000-000000000002")!
    public static let id_draftReply          = UUID(uuidString: "22222222-0000-0000-0000-000000000003")!
    public static let id_submitTimesheet     = UUID(uuidString: "22222222-0000-0000-0000-000000000004")!
    public static let id_run5km              = UUID(uuidString: "22222222-0000-0000-0000-000000000005")!
    public static let id_stretchFirst        = UUID(uuidString: "22222222-0000-0000-0000-000000000006")!
    public static let id_read30              = UUID(uuidString: "22222222-0000-0000-0000-000000000007")!
    public static let id_bookDentist         = UUID(uuidString: "22222222-0000-0000-0000-000000000008")!
    public static let id_confirmPrefTime     = UUID(uuidString: "22222222-0000-0000-0000-000000000009")!
    public static let id_renewPassport       = UUID(uuidString: "22222222-0000-0000-0000-00000000000A")!
    public static let id_callMum             = UUID(uuidString: "22222222-0000-0000-0000-00000000000B")!
    public static let id_birthdayGiftAlex    = UUID(uuidString: "22222222-0000-0000-0000-00000000000C")!
    public static let id_roadmapIdeas        = UUID(uuidString: "22222222-0000-0000-0000-00000000000D")!
    public static let id_designSchema        = UUID(uuidString: "22222222-0000-0000-0000-00000000000E")!
    public static let id_buildSync           = UUID(uuidString: "22222222-0000-0000-0000-00000000000F")!
    public static let id_testSyncEndToEnd    = UUID(uuidString: "22222222-0000-0000-0000-000000000010")!
    public static let id_buildEditor         = UUID(uuidString: "22222222-0000-0000-0000-000000000011")!

    /// Maps human names → stable UUIDs. Useful for tests in the host bundle.
    public static let testIds: [String: UUID] = [
        "payPhoneBill":      id_payPhoneBill,
        "emailSarah":        id_emailSarah,
        "draftReply":        id_draftReply,
        "submitTimesheet":   id_submitTimesheet,
        "run5km":            id_run5km,
        "stretchFirst":      id_stretchFirst,
        "read30":            id_read30,
        "bookDentist":       id_bookDentist,
        "confirmPrefTime":   id_confirmPrefTime,
        "renewPassport":     id_renewPassport,
        "callMum":           id_callMum,
        "birthdayGiftAlex":  id_birthdayGiftAlex,
        "roadmapIdeas":      id_roadmapIdeas,
        "designSchema":      id_designSchema,
        "buildSync":         id_buildSync,
        "testSyncEndToEnd":  id_testSyncEndToEnd,
        "buildEditor":       id_buildEditor
    ]

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
                id: id_payPhoneBill,
                type: .task,
                title: "Pay phone bill",
                listId: inboxId,
                tags: ["finance"],
                due: yesterday19,
                flagged: true
            )
        )

        // ── Work: flat list with a nested parent/child item ───────────
        items.append(
            Item(
                id: id_emailSarah,
                type: .task,
                title: "Email Sarah about onboarding",
                listId: "work",
                tags: ["work"],
                due: today9
            )
        )
        items.append(
            Item(
                id: id_draftReply,
                type: .task,
                title: "Draft reply",
                listId: "work",
                parentId: id_emailSarah,
                tags: ["work"]
            )
        )
        items.append(
            Item(
                id: id_submitTimesheet,
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
        items.append(
            Item(
                id: id_run5km,
                type: .task,
                title: "Run 5km",
                listId: "personal",
                section: healthSectionId.uuidString,
                tags: ["health"],
                due: today18
            )
        )
        items.append(
            Item(
                id: id_stretchFirst,
                type: .task,
                title: "Stretch first",
                listId: "personal",
                section: healthSectionId.uuidString,
                parentId: id_run5km,
                tags: ["health"]
            )
        )
        items.append(
            Item(
                id: id_read30,
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
        items.append(
            Item(
                id: id_bookDentist,
                type: .task,
                title: "Book dentist appointment",
                listId: "personal",
                section: adminSectionId.uuidString,
                tags: ["health", "admin"]
            )
        )
        items.append(
            Item(
                id: id_confirmPrefTime,
                type: .task,
                title: "Confirm preferred time",
                listId: "personal",
                section: adminSectionId.uuidString,
                parentId: id_bookDentist,
                tags: ["admin"]
            )
        )
        items.append(
            Item(
                id: id_renewPassport,
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
                id: id_callMum,
                type: .task,
                title: "Call Mum",
                listId: "personal",
                tags: ["family"],
                due: today18
            )
        )
        items.append(
            Item(
                id: id_birthdayGiftAlex,
                type: .task,
                title: "Birthday gift for Alex",
                listId: "personal",
                tags: ["family"]
            )
        )

        // ── Projects tree: items at each level of list nesting ────────
        items.append(
            Item(
                id: id_roadmapIdeas,
                type: .note,
                title: "Roadmap ideas",
                body: "Rough sketch of upcoming projects.\n",
                listId: "projects"
            )
        )
        items.append(
            Item(
                id: id_designSchema,
                type: .task,
                title: "Design schema",
                listId: "projects-sideapp",
                tags: ["work"]
            )
        )
        items.append(
            Item(
                id: id_buildSync,
                type: .task,
                title: "Build sync",
                listId: "projects-sideapp-sprint1",
                tags: ["work"],
                due: tomorrow14
            )
        )
        items.append(
            Item(
                id: id_testSyncEndToEnd,
                type: .task,
                title: "Test sync end-to-end",
                listId: "projects-sideapp-sprint1",
                parentId: id_buildSync,
                tags: ["work"]
            )
        )
        items.append(
            Item(
                id: id_buildEditor,
                type: .task,
                title: "Build editor",
                listId: "projects-sideapp-sprint1",
                tags: ["work"]
            )
        )

        return items
    }
}
