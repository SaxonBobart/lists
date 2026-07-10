import Observation
import SwiftUI
import UIKit

final class MarkdownFormatInputView: UIView {
    private enum Metrics {
        static let height: CGFloat = 292
    }

    fileprivate static let styleItems: [MarkdownFormatItem] = [
        MarkdownFormatItem(title: "Body", shortTitle: "Body", symbol: nil, action: .paragraph, accessibilityLabel: "Body"),
        MarkdownFormatItem(title: "Heading 1", shortTitle: nil, symbol: nil, action: .heading(1), accessibilityLabel: "Heading 1"),
        MarkdownFormatItem(title: "Heading 2", shortTitle: nil, symbol: nil, action: .heading(2), accessibilityLabel: "Heading 2"),
        MarkdownFormatItem(title: "Heading 3", shortTitle: nil, symbol: nil, action: .heading(3), accessibilityLabel: "Heading 3"),
        MarkdownFormatItem(title: "Heading 4", shortTitle: nil, symbol: nil, action: .heading(4), accessibilityLabel: "Heading 4"),
        MarkdownFormatItem(title: "Heading 5", shortTitle: nil, symbol: nil, action: .heading(5), accessibilityLabel: "Heading 5"),
        MarkdownFormatItem(title: "Heading 6", shortTitle: nil, symbol: nil, action: .heading(6), accessibilityLabel: "Heading 6")
    ]

    fileprivate static let inlineItems: [MarkdownFormatItem] = [
        MarkdownFormatItem(title: nil, symbol: "bold", action: .bold, accessibilityLabel: "Bold"),
        MarkdownFormatItem(title: nil, symbol: "italic", action: .italic, accessibilityLabel: "Italic"),
        MarkdownFormatItem(title: nil, symbol: "strikethrough", action: .strikethrough, accessibilityLabel: "Strikethrough"),
        MarkdownFormatItem(title: nil, symbol: "curlybraces", action: .code, accessibilityLabel: "Inline Code")
    ]

    fileprivate static let highlightItem = MarkdownFormatItem(
        title: nil,
        symbol: "highlighter",
        action: .highlight,
        accessibilityLabel: "Highlight"
    )

    fileprivate static let blockItems: [MarkdownFormatItem] = [
        MarkdownFormatItem(title: nil, symbol: "list.bullet", action: .bullet, accessibilityLabel: "Bulleted List"),
        MarkdownFormatItem(title: nil, symbol: "list.number", action: .numbered, accessibilityLabel: "Numbered List"),
        MarkdownFormatItem(title: nil, symbol: "checkmark.square", action: .task, accessibilityLabel: "Checklist"),
        MarkdownFormatItem(title: nil, symbol: "quote.bubble", action: .blockquote, accessibilityLabel: "Quote"),
        MarkdownFormatItem(title: nil, symbol: "decrease.indent", action: .outdent, accessibilityLabel: "Outdent"),
        MarkdownFormatItem(title: nil, symbol: "increase.indent", action: .indent, accessibilityLabel: "Indent")
    ]

    static let formatAccessibilityIdentifiers: [String] =
        (styleItems + inlineItems + [highlightItem] + blockItems).map(\.action.accessibilityId)

    private let hostingController: UIHostingController<MarkdownFormatPanel>

    init(action: @escaping (ToolbarAction) -> Void,
         close: @escaping () -> Void) {
        let panel = MarkdownFormatPanel(
            styleItems: Self.styleItems,
            inlineItems: Self.inlineItems,
            highlightItem: Self.highlightItem,
            blockItems: Self.blockItems,
            formatState: MarkdownFormatState(),
            action: action,
            close: close
        )
        hostingController = UIHostingController(rootView: panel)
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Metrics.height))
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isOpaque = false
        backgroundColor = .clear
        setupHostingView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Metrics.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: Metrics.height)
    }

    private func setupHostingView() {
        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.isOpaque = false
        hostedView.backgroundColor = .clear
        addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

@MainActor
@Observable
final class MarkdownFormatPanelSession: Identifiable {
    let id = UUID()

    private(set) var formatState = MarkdownFormatState()

    @ObservationIgnored private weak var textView: UITextView?
    @ObservationIgnored private weak var coordinator: EditorCoordinator?
    @ObservationIgnored private var originalInputView: UIView?
    @ObservationIgnored private var originalInputAccessoryView: UIView?
    @ObservationIgnored private var emptyInputView: UIView?
    @ObservationIgnored private var emptyAccessoryView: UIView?
    @ObservationIgnored private var isSuppressingKeyboard = false

    init(textView: UITextView, coordinator: EditorCoordinator) {
        self.textView = textView
        self.coordinator = coordinator
        refreshFormatState()
    }

    func perform(_ action: ToolbarAction) {
        coordinator?.handleToolbarAction(action)
        refreshFormatState()
    }

    func suppressKeyboard() {
        guard let textView, !isSuppressingKeyboard else { return }
        originalInputView = textView.inputView
        originalInputAccessoryView = textView.inputAccessoryView

        let inputView = EmptyKeyboardView()
        let accessoryView = EmptyKeyboardView()
        emptyInputView = inputView
        emptyAccessoryView = accessoryView

        textView.inputView = inputView
        textView.inputAccessoryView = accessoryView
        textView.reloadInputViews()
        coordinator?.formatPanelSession = self
        refreshFormatState()
        isSuppressingKeyboard = true
    }

    func restoreKeyboard(refocusesTextView: Bool = true) {
        guard let textView else { return }
        if isSuppressingKeyboard {
            if coordinator?.formatPanelSession === self {
                coordinator?.formatPanelSession = nil
            }
            textView.inputView = originalInputView
            textView.inputAccessoryView = originalInputAccessoryView
            originalInputView = nil
            originalInputAccessoryView = nil
            emptyInputView = nil
            emptyAccessoryView = nil
            textView.reloadInputViews()
            isSuppressingKeyboard = false
        }
        if refocusesTextView {
            textView.becomeFirstResponder()
        }
    }

    func refreshFormatState() {
        guard let textView else {
            formatState = MarkdownFormatState()
            return
        }
        formatState = MarkdownFormatState.detect(in: textView.textStorage.string,
                                                 selection: textView.selectedRange)
    }
}

private final class EmptyKeyboardView: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 0)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: 0)
    }
}

struct MarkdownFormatPanelOverlay: View {
    let session: MarkdownFormatPanelSession
    let onClose: () -> Void

    var body: some View {
        MarkdownFormatPanel(
            styleItems: MarkdownFormatInputView.styleItems,
            inlineItems: MarkdownFormatInputView.inlineItems,
            highlightItem: MarkdownFormatInputView.highlightItem,
            blockItems: MarkdownFormatInputView.blockItems,
            formatState: session.formatState,
            action: { session.perform($0) },
            close: close
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .accessibilityIdentifier("markdown.format.panel")
    }

    private func close() {
        onClose()
        session.restoreKeyboard()
    }
}

private struct MarkdownFormatItem: Identifiable, Hashable {
    let title: String?
    var shortTitle: String?
    let symbol: String?
    let action: ToolbarAction
    let accessibilityLabel: String

    var id: String { action.accessibilityId }
}

private struct MarkdownFormatPanel: View {
    private enum Metrics {
        static let panelHorizontalPadding: CGFloat = 18
        static let segmentWidth: CGFloat = 54
        static let segmentHeight: CGFloat = 42
        static let segmentGap: CGFloat = 2
        static let segmentRadius: CGFloat = 21
        static let symbolPointSize: CGFloat = 20
    }

    let styleItems: [MarkdownFormatItem]
    let inlineItems: [MarkdownFormatItem]
    let highlightItem: MarkdownFormatItem
    let blockItems: [MarkdownFormatItem]
    let formatState: MarkdownFormatState
    let action: (ToolbarAction) -> Void
    let close: () -> Void

    private enum SegmentPosition {
        case single
        case first
        case middle
        case last
    }

    var body: some View {
        panel
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(Color.clear)
    }

    private var panel: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                header
                styleRow
                controlRows
            }
            .padding(.horizontal, Metrics.panelHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: panelShape)
            .accessibilityElement(children: .contain)
        }
    }

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(
            topLeading: 34,
            bottomLeading: 0,
            bottomTrailing: 0,
            topTrailing: 34
        ), style: .continuous)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Format")
                .font(.system(size: 27, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("markdown.format.title")

            Spacer(minLength: 12)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 26, weight: .medium))
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("Close format")
            .accessibilityIdentifier("markdown.format.close")
        }
        .frame(height: 50)
    }

    private var styleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 22) {
                ForEach(styleItems) { item in
                    styleButton(item)
                }
            }
            .padding(.horizontal, Metrics.panelHorizontalPadding + 2)
        }
        .padding(.horizontal, -Metrics.panelHorizontalPadding)
        .frame(height: 48)
    }

    private var controlRows: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                segmentedGroup(inlineItems)
                Spacer(minLength: 16)
                highlightGroup
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                segmentedGroup(Array(blockItems.prefix(4)))
                Spacer(minLength: 16)
                segmentedGroup(Array(blockItems.suffix(2)))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 2)
    }

    private func styleButton(_ item: MarkdownFormatItem) -> some View {
        let selected = formatState.isActive(item.action)

        return Button {
            action(item.action)
        } label: {
            Text(item.title ?? "")
            .font(stylePreviewFont(for: item.action))
            .lineLimit(1)
            .minimumScaleFactor(0.88)
            .allowsTightening(true)
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 44)
            .padding(.horizontal, selected ? 20 : 4)
            .background(styleButtonBackground(selected), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : .primary)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier(item.action.accessibilityId)
    }

    private func styleButtonBackground(_ selected: Bool) -> Color {
        selected ? ListsTokens.accent : .clear
    }

    private func stylePreviewFont(for action: ToolbarAction) -> Font {
        switch action {
        case .paragraph:
            return .title3
        case .heading(let level):
            switch level {
            case 1: return .title.bold()
            case 2: return .title2.bold()
            case 3: return .title3.bold()
            case 4: return .headline.bold()
            case 5: return .subheadline.bold()
            case 6: return .footnote.bold()
            default: return .subheadline.bold()
            }
        default:
            return .body
        }
    }

    private func segmentedGroup(_ items: [MarkdownFormatItem]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                iconButton(item, index: index, count: items.count)
            }
        }
        .frame(
            width: CGFloat(items.count) * Metrics.segmentWidth
                + CGFloat(max(0, items.count - 1)) * Metrics.segmentGap,
            height: Metrics.segmentHeight
        )
    }

    private var highlightGroup: some View {
        HStack(spacing: 2) {
            iconButton(highlightItem, index: 0, count: 2)
            highlightPreview
                .frame(width: Metrics.segmentWidth, height: Metrics.segmentHeight)
                .background(segmentBackground(active: false, disabled: false), in: segmentShape(index: 1, count: 2))
                .accessibilityHidden(true)
        }
        .frame(
            width: Metrics.segmentWidth * 2 + Metrics.segmentGap,
            height: Metrics.segmentHeight
        )
    }

    private var highlightPreview: some View {
        Circle()
            .fill(ListsTokens.Markdown.highlightForeground)
            .frame(width: 18, height: 18)
    }

    private func iconButton(_ item: MarkdownFormatItem, index: Int, count: Int) -> some View {
        let active = formatState.isActive(item.action)
        let disabled = formatState.isDisabled(item.action)

        return Button {
            action(item.action)
        } label: {
            Image(systemName: item.symbol ?? "")
                .font(.system(size: Metrics.symbolPointSize, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: Metrics.segmentWidth, height: Metrics.segmentHeight)
                .background(segmentBackground(active: active, disabled: disabled),
                            in: segmentShape(index: index, count: count))
                .contentShape(segmentShape(index: index, count: count))
        }
        .buttonStyle(.plain)
        .foregroundStyle(buttonForeground(active: active, disabled: disabled))
        .disabled(disabled)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier(item.action.accessibilityId)
    }

    private func segmentBackground(active: Bool, disabled: Bool) -> Color {
        if active {
            return ListsTokens.accent
        }
        return Color(uiColor: .secondarySystemFill)
            .opacity(disabled ? 0.52 : 1)
    }

    private func buttonForeground(active: Bool, disabled: Bool) -> Color {
        if active {
            return .white
        }
        if disabled {
            return Color(uiColor: .tertiaryLabel)
        }
        return .primary
    }

    private func segmentShape(index: Int, count: Int) -> UnevenRoundedRectangle {
        segmentShape(position: segmentPosition(index: index, count: count))
    }

    private func segmentPosition(index: Int, count: Int) -> SegmentPosition {
        if count <= 1 { return .single }
        if index == 0 { return .first }
        if index == count - 1 { return .last }
        return .middle
    }

    private func segmentShape(position: SegmentPosition) -> UnevenRoundedRectangle {
        let outer: CGFloat = Metrics.segmentRadius
        let inner: CGFloat = 0

        switch position {
        case .single:
            return UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: outer,
                bottomLeading: outer,
                bottomTrailing: outer,
                topTrailing: outer
            ), style: .continuous)
        case .first:
            return UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: outer,
                bottomLeading: outer,
                bottomTrailing: inner,
                topTrailing: inner
            ), style: .continuous)
        case .middle:
            return UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: inner,
                bottomLeading: inner,
                bottomTrailing: inner,
                topTrailing: inner
            ), style: .continuous)
        case .last:
            return UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: inner,
                bottomLeading: inner,
                bottomTrailing: outer,
                topTrailing: outer
            ), style: .continuous)
        }
    }
}

struct MarkdownFormatState: Equatable {
    var styleAction: ToolbarAction? = .paragraph
    var activeActions: Set<ToolbarAction> = []
    var disabledActions: Set<ToolbarAction> = [.outdent]

    func isActive(_ action: ToolbarAction) -> Bool {
        if styleAction == action {
            return true
        }
        return activeActions.contains(action)
    }

    func isDisabled(_ action: ToolbarAction) -> Bool {
        disabledActions.contains(action)
    }

    static func detect(in source: String, selection: NSRange) -> MarkdownFormatState {
        let ns = source as NSString
        let selection = MarkdownSyntax.clamped(selection, length: ns.length)
        let lines = MarkdownSyntax.lineRanges(in: ns, selection: selection)
        let lineKinds = lines.map { MarkdownSyntax.lineKind(in: MarkdownSyntax.lineContent(in: ns, range: $0)) }
        let styleAction = commonStyleAction(in: lineKinds)
        var activeActions = Set<ToolbarAction>()

        if allLines(lineKinds, are: .bullet) { activeActions.insert(.bullet) }
        if allLines(lineKinds, are: .numbered) { activeActions.insert(.numbered) }
        if allLines(lineKinds, are: .task) { activeActions.insert(.task) }
        if allLines(lineKinds, are: .quote) { activeActions.insert(.blockquote) }

        let inlineSpans = MarkdownSyntax.inlineSpans(in: source)
        for action in [ToolbarAction.bold, .italic, .strikethrough, .code, .highlight] {
            guard let kind = MarkdownSyntax.inlineKind(for: action) else { continue }
            if MarkdownSyntax.selection(selection,
                                        isActiveIn: inlineSpans.filter({ $0.kind == kind })) {
                activeActions.insert(action)
            }
        }

        var disabledActions = Set<ToolbarAction>()
        if !lines.contains(where: { lineCanOutdent(MarkdownSyntax.lineContent(in: ns, range: $0)) }) {
            disabledActions.insert(.outdent)
        }

        return MarkdownFormatState(styleAction: styleAction,
                                   activeActions: activeActions,
                                   disabledActions: disabledActions)
    }

    private static func commonStyleAction(in lineKinds: [MarkdownSyntax.LineKind]) -> ToolbarAction? {
        guard let first = lineKinds.first else { return .paragraph }
        guard lineKinds.allSatisfy({ $0 == first }) else { return nil }
        switch first {
        case .heading(let level):
            return .heading(level)
        default:
            return .paragraph
        }
    }

    private static func allLines(_ lineKinds: [MarkdownSyntax.LineKind], are target: MarkdownSyntax.LineKind) -> Bool {
        guard !lineKinds.isEmpty else { return false }
        return lineKinds.allSatisfy { $0 == target }
    }

    private static func lineCanOutdent(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first == " " || first == "\t"
    }
}
