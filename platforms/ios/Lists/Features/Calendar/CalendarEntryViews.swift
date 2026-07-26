import SwiftUI

struct CalendarEntryChip: View {
    let entry: CalendarEntry
    let color: Color
    var compact = false
    let onOpen: () -> Void
    var onDuplicate: (() -> Void)?
    var instanceIdentifier: String?

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 3) {
                if entry.status == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: compact ? 6 : 8, weight: .bold))
                } else if entry.status == .missed {
                    Image(systemName: "xmark")
                        .font(.system(size: compact ? 6 : 8, weight: .bold))
                }
                if !compact {
                    Text(entry.title.isEmpty ? "Untitled" : entry.title)
                        .lineLimit(1)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(entry.status == .missed ? .secondary : color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? 2 : 4)
            .padding(.vertical, compact ? 1 : 3)
            .background(
                color.opacity(entry.status == .completed ? 0.12 : 0.18),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .opacity(entry.isProjected ? 0.68 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onDuplicate {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(
            instanceIdentifier
                ?? "calendar.entry.\(entry.id.itemId.uuidString).\(entry.id.source.rawValue)"
        )
    }

    private var accessibilityLabel: String {
        var parts = [entry.title.isEmpty ? "Untitled" : entry.title]
        if entry.isAllDay {
            parts.append("all day")
        } else {
            parts.append(entry.start.formatted(date: .omitted, time: .shortened))
        }
        if entry.status == .completed { parts.append("completed") }
        if entry.status == .missed { parts.append("missed") }
        if entry.isProjected { parts.append("future occurrence") }
        return parts.joined(separator: ", ")
    }
}

struct CalendarAgendaEntryRow: View {
    let entry: CalendarEntry
    let color: Color
    let canToggle: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    var onDuplicate: (() -> Void)?
    var instanceIdentifier: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if entry.isCompletable {
                Button(action: onToggle) {
                    Image(systemName: entry.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(entry.status == .completed ? color : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canToggle)
                .opacity(canToggle ? 1 : 0.45)
                .accessibilityLabel(entry.status == .completed ? "Mark incomplete" : "Mark complete")
                .accessibilityIdentifier(
                    "\(resolvedIdentifier).toggle"
                )
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 34)
                    .accessibilityHidden(true)
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title.isEmpty ? "Untitled" : entry.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .strikethrough(entry.status == .completed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Label(timeLabel, systemImage: entry.type.calendarSystemImage)
                        if entry.hasRecurrence {
                            Image(systemName: "repeat")
                        }
                        if entry.flagged {
                            Image(systemName: "flag.fill")
                        }
                        if entry.status == .missed {
                            Text("Missed")
                        } else if entry.isProjected {
                            Text("Future occurrence")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contextMenu {
            if let onDuplicate {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            }
        }
        .accessibilityIdentifier(resolvedIdentifier)
    }

    private var timeLabel: String {
        if entry.isAllDay { return "All day" }
        return "\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))"
    }

    private var resolvedIdentifier: String {
        instanceIdentifier
            ?? "calendar.agenda.entry.\(entry.itemId.uuidString).\(entry.id.source.rawValue)"
    }
}

extension Item.ItemType {
    var calendarSystemImage: String {
        switch self {
        case .task:  return "checkmark.circle"
        case .habit: return "repeat"
        case .note:  return "text.document"
        case .event: return "calendar"
        }
    }
}
