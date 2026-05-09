import Foundation

/// First-launch seed data — created once when no Lists folder exists on disk.
public enum SampleData {
    public static func seedItems(for listId: String, now: Date = .now, calendar: Calendar = .current) -> [Item] {
        let todayMorning = calendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: now
        ) ?? now

        let yesterdayEvening = calendar.date(
            byAdding: .day, value: -1,
            to: calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
        ) ?? now

        let tomorrowAfternoon = calendar.date(
            byAdding: .day, value: 1,
            to: calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now) ?? now
        ) ?? now

        return [
            Item(
                type: .task,
                title: "Pay phone bill",
                body: "Due before close of business.\n",
                listId: listId,
                tags: ["finance"],
                due: yesterdayEvening,
                priority: .medium,
                flagged: true
            ),
            Item(
                type: .task,
                title: "Stand-up at 9am",
                body: "Quick check-in with the team.\n",
                listId: listId,
                due: todayMorning
            ),
            Item(
                type: .task,
                title: "Pick up dry cleaning",
                body: "",
                listId: listId,
                due: tomorrowAfternoon
            )
        ]
    }
}
