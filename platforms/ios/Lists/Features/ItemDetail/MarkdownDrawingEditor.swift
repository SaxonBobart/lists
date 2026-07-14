import PaperKit
import PencilKit
import SwiftUI

enum MarkdownPaperStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case plain
    case ruled
    case grid
    case dotGrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: "Plain"
        case .ruled: "Ruled"
        case .grid: "Grid"
        case .dotGrid: "Dot Grid"
        }
    }

    var systemImage: String {
        switch self {
        case .plain: "rectangle"
        case .ruled: "line.3.horizontal"
        case .grid: "grid"
        case .dotGrid: "circle.grid.3x3"
        }
    }

    fileprivate func draw(
        in context: CGContext,
        rect: CGRect,
        darkMode: Bool,
        displayScale: CGFloat
    ) {
        let traits = UITraitCollection(userInterfaceStyle: darkMode ? .dark : .light)
        let background = UIColor.systemBackground.resolvedColor(with: traits)
        context.setFillColor(background.cgColor)
        context.fill(rect)

        guard self != .plain else { return }
        let separator = UIColor.separator.resolvedColor(with: traits).withAlphaComponent(0.42)
        context.setStrokeColor(separator.cgColor)
        context.setFillColor(separator.cgColor)
        context.setLineWidth(1 / max(displayScale, 1))

        let spacing: CGFloat = 32
        switch self {
        case .plain:
            break
        case .ruled:
            var y = spacing
            while y < rect.maxY {
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += spacing
            }
            context.strokePath()
        case .grid:
            var y = spacing
            while y < rect.maxY {
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += spacing
            }
            var x = spacing
            while x < rect.maxX {
                context.move(to: CGPoint(x: x, y: rect.minY))
                context.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += spacing
            }
            context.strokePath()
        case .dotGrid:
            let radius: CGFloat = 1.2
            var y = spacing
            while y < rect.maxY {
                var x = spacing
                while x < rect.maxX {
                    context.fillEllipse(in: CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

struct MarkdownDrawingDocument: Sendable {
    private struct Envelope: Codable {
        let format: String
        let version: Int
        let paperStyle: MarkdownPaperStyle
        let markupData: Data
    }

    private static let format = "io.github.saxonbobart.lists.paper-markup"
    private static let defaultBounds = CGRect(x: 0, y: 0, width: 1_024, height: 1_365)

    var markup: PaperMarkup
    var paperStyle: MarkdownPaperStyle

    var hasContent: Bool {
        let frame = markup.contentsRenderFrame
        return frame.isEmpty == false && frame.isNull == false && frame.isInfinite == false
    }

    static func blank(paperStyle: MarkdownPaperStyle = .plain) -> Self {
        var markup = PaperMarkup(bounds: defaultBounds)
        makeBackgroundTransparent(&markup)
        return Self(markup: markup, paperStyle: paperStyle)
    }

    init(markup: PaperMarkup, paperStyle: MarkdownPaperStyle) {
        var markup = markup
        Self.makeBackgroundTransparent(&markup)
        self.markup = markup
        self.paperStyle = paperStyle
    }

    init(dataRepresentation data: Data) throws {
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           envelope.format == Self.format,
           envelope.version == 1 {
            self.init(
                markup: try PaperMarkup(dataRepresentation: envelope.markupData),
                paperStyle: envelope.paperStyle
            )
            return
        }

        // PaperKit's own serialized data is accepted so exported sidecars can
        // still be reopened if they are separated from the Lists envelope.
        if let markup = try? PaperMarkup(dataRepresentation: data) {
            self.init(markup: markup, paperStyle: .plain)
            return
        }

        // Drawings created before the PaperKit editor remain losslessly
        // editable: import the original strokes into a new PaperMarkup model.
        let drawing = try PKDrawing(data: data)
        let bounds = Self.canvasBounds(containing: drawing.bounds)
        var markup = PaperMarkup(bounds: bounds)
        markup.append(contentsOf: drawing)
        self.init(markup: markup, paperStyle: .plain)
    }

    func dataRepresentation() async throws -> Data {
        let markupData = try await markup.dataRepresentation()
        return try JSONEncoder().encode(Envelope(
            format: Self.format,
            version: 1,
            paperStyle: paperStyle,
            markupData: markupData
        ))
    }

    @MainActor
    func previewImage(darkMode: Bool) async throws -> UIImage {
        let paperBounds = markup.bounds.isEmpty ? Self.defaultBounds : markup.bounds
        let maximumDimension: CGFloat = 1_600
        let scale = min(
            maximumDimension / max(paperBounds.width, paperBounds.height),
            2
        )
        let pixelWidth = max(1, Int(ceil(paperBounds.width * scale)))
        let pixelHeight = max(1, Int(ceil(paperBounds.height * scale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AttachmentStorageError.emptyData
        }

        let renderFrame = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        paperStyle.draw(
            in: context,
            rect: renderFrame,
            darkMode: darkMode,
            displayScale: scale
        )
        await markup.draw(
            in: context,
            frame: renderFrame,
            options: RenderingOptions(darkUserInterfaceStyle: darkMode)
        )
        guard let image = context.makeImage() else {
            throw AttachmentStorageError.emptyData
        }
        return UIImage(cgImage: image)
    }

    private static func canvasBounds(containing content: CGRect) -> CGRect {
        guard content.isEmpty == false, content.isNull == false else { return defaultBounds }
        return CGRect(
            x: 0,
            y: 0,
            width: max(defaultBounds.width, content.maxX + 96),
            height: max(defaultBounds.height, content.maxY + 96)
        )
    }

    private static func makeBackgroundTransparent(_ markup: inout PaperMarkup) {
        if #available(iOS 27.0, *) {
            markup.backgroundColor = UIColor.clear.cgColor
        }
    }
}

struct MarkdownDrawingEditor: View {
    let isEditing: Bool
    let onComplete: (MarkdownDrawingDocument?) -> Void
    @State private var document: MarkdownDrawingDocument
    @State private var presentObjectsToken = UUID()

    init(
        document: MarkdownDrawingDocument = .blank(),
        isEditing: Bool = false,
        onComplete: @escaping (MarkdownDrawingDocument?) -> Void
    ) {
        self.isEditing = isEditing
        self.onComplete = onComplete
        _document = State(initialValue: document)
    }

    var body: some View {
        NavigationStack {
            PaperCanvas(document: $document, presentObjectsToken: presentObjectsToken)
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Drawing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { onComplete(nil) }
                            .accessibilityIdentifier("document.drawing.cancel")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        paperMenu
                        Button("Add Object", systemImage: "square.on.circle") {
                            presentObjectsToken = UUID()
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("document.drawing.objects")

                        Button(isEditing ? "Save" : "Add") { onComplete(document) }
                            .fontWeight(.semibold)
                            .disabled(document.hasContent == false)
                            .accessibilityIdentifier(isEditing ? "document.drawing.save" : "document.drawing.add")
                    }
                }
        }
        .accessibilityIdentifier("document.drawing.editor")
    }

    private var paperMenu: some View {
        Menu("Paper", systemImage: document.paperStyle.systemImage) {
            ForEach(MarkdownPaperStyle.allCases) { style in
                Button {
                    document.paperStyle = style
                } label: {
                    Label(style.title, systemImage: style.systemImage)
                }
            }
        }
        .accessibilityIdentifier("document.drawing.paper")
    }
}

private struct PaperCanvas: UIViewControllerRepresentable {
    @Binding var document: MarkdownDrawingDocument
    let presentObjectsToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PaperMarkupViewController {
        let controller = PaperMarkupViewController(
            markup: document.markup,
            supportedFeatureSet: .latest
        )
        controller.delegate = context.coordinator
        controller.isEditable = true
        controller.directTouchAutomaticallyDraws = true
        controller.zoomRange = 0.35...6
        controller.view.accessibilityIdentifier = "document.drawing.canvas"
        context.coordinator.controller = controller
        context.coordinator.lastObjectsToken = presentObjectsToken
        context.coordinator.updateBackground(style: document.paperStyle, on: controller)
        DispatchQueue.main.async { context.coordinator.activateToolPicker() }
        return controller
    }

    func updateUIViewController(_ controller: PaperMarkupViewController, context: Context) {
        context.coordinator.parent = self
        if controller.markup != document.markup {
            controller.markup = document.markup
        }
        context.coordinator.updateBackground(style: document.paperStyle, on: controller)
        if context.coordinator.lastObjectsToken != presentObjectsToken {
            context.coordinator.lastObjectsToken = presentObjectsToken
            context.coordinator.presentObjectPicker()
        }
    }

    @MainActor
    final class Coordinator: NSObject,
                             @preconcurrency PaperMarkupViewController.Delegate,
                             @preconcurrency MarkupEditViewController.Delegate,
                             UIPopoverPresentationControllerDelegate {
        var parent: PaperCanvas
        weak var controller: PaperMarkupViewController?
        var lastObjectsToken: UUID?
        private let toolPicker = PKToolPicker()
        private var isToolPickerAttached = false
        private weak var paperBackground: DrawingPaperBackgroundView?

        init(parent: PaperCanvas) {
            self.parent = parent
        }

        func activateToolPicker() {
            guard let controller else { return }
            if isToolPickerAttached == false {
                toolPicker.addObserver(controller)
                isToolPickerAttached = true
            }
            controller.pencilKitResponderState.activeToolPicker = toolPicker
            controller.pencilKitResponderState.toolPickerVisibility = .visible
            toolPicker.setVisible(true, forFirstResponder: controller)
            controller.becomeFirstResponder()
        }

        private func suspendToolPicker() {
            guard let controller else { return }
            toolPicker.setVisible(false, forFirstResponder: controller)
            controller.pencilKitResponderState.activeToolPicker = toolPicker
            controller.pencilKitResponderState.toolPickerVisibility = .inactive
            if isToolPickerAttached {
                toolPicker.removeObserver(controller)
                isToolPickerAttached = false
            }
            controller.resignFirstResponder()
        }

        func updateBackground(style: MarkdownPaperStyle, on controller: PaperMarkupViewController) {
            if let paperBackground {
                guard paperBackground.style != style else { return }
                paperBackground.style = style
                paperBackground.setNeedsDisplay()
                return
            }
            let background = DrawingPaperBackgroundView(style: style)
            background.isUserInteractionEnabled = false
            controller.contentView = background
            paperBackground = background
        }

        func presentObjectPicker() {
            guard let controller, controller.presentedViewController == nil else { return }
            let picker = MarkupEditViewController(supportedFeatureSet: .latest)
            picker.delegate = self
            picker.modalPresentationStyle = .popover
            let presentationController = picker.popoverPresentationController
            presentationController?.delegate = self
            presentationController?.sourceView = controller.view
            presentationController?.sourceRect = CGRect(
                x: controller.view.bounds.maxX - 28,
                y: controller.view.safeAreaInsets.top + 28,
                width: 1,
                height: 1
            )
            suspendToolPicker()
            controller.present(picker, animated: true)
        }

        func adaptivePresentationStyle(
            for _: UIPresentationController
        ) -> UIModalPresentationStyle {
            .none
        }

        func markupEditViewController(
            _ picker: MarkupEditViewController,
            insertNewShape type: ShapeConfiguration.Shape
        ) {
            controller?.markupEditViewController(picker, insertNewShape: type)
            finishObjectInsertion(picker)
        }

        func markupEditViewControllerInsertNewTextbox(_ picker: MarkupEditViewController) {
            controller?.markupEditViewControllerInsertNewTextbox(picker)
            finishObjectInsertion(picker)
        }

        func markupEditViewController(
            _ picker: MarkupEditViewController,
            insertNewLineWithStartMarker startMarker: Bool,
            endMarker: Bool
        ) {
            controller?.markupEditViewController(
                picker,
                insertNewLineWithStartMarker: startMarker,
                endMarker: endMarker
            )
            finishObjectInsertion(picker)
        }

        func markupEditViewController(
            _ picker: MarkupEditViewController,
            insertNewContents contents: PaperMarkup
        ) {
            controller?.markupEditViewController(picker, insertNewContents: contents)
            finishObjectInsertion(picker)
        }

        func presentationControllerDidDismiss(_: UIPresentationController) {
            activateToolPicker()
        }

        private func finishObjectInsertion(_ picker: MarkupEditViewController) {
            picker.dismiss(animated: true) { [weak self] in
                self?.activateToolPicker()
            }
        }

        func paperMarkupViewControllerDidChangeMarkup(_ paperMarkupViewController: PaperMarkupViewController) {
            guard let markup = paperMarkupViewController.markup else { return }
            parent.document.markup = markup
        }

        func paperMarkupViewControllerDidChangeSelection(_: PaperMarkupViewController) {}
        func paperMarkupViewControllerDidBeginDrawing(_: PaperMarkupViewController) {}
        func paperMarkupViewControllerDidChangeContentVisibleFrame(_: PaperMarkupViewController) {}

        @available(iOS 27.0, *)
        func paperMarkupViewController(
            _: PaperMarkupViewController,
            didTapAdornmentWithID _: UUID
        ) {}

        @available(iOS 27.0, *)
        func paperMarkupViewController(
            _: PaperMarkupViewController,
            willUpdateAdornmentWithID _: UUID,
            toProposedAnchor proposedAnchor: MarkupAdornment.Anchor
        ) -> MarkupAdornment.Anchor? {
            proposedAnchor
        }

        @available(iOS 27.0, *)
        func paperMarkupViewController(
            _: PaperMarkupViewController,
            didUpdateAdornmentWithID _: UUID,
            toAnchor _: MarkupAdornment.Anchor
        ) {}
    }
}

private final class DrawingPaperBackgroundView: UIView {
    var style: MarkdownPaperStyle

    init(style: MarkdownPaperStyle) {
        self.style = style
        super.init(frame: .zero)
        isOpaque = true
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: DrawingPaperBackgroundView, _: UITraitCollection) in
            view.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        style.draw(
            in: context,
            rect: bounds,
            darkMode: traitCollection.userInterfaceStyle == .dark,
            displayScale: traitCollection.displayScale
        )
    }
}
