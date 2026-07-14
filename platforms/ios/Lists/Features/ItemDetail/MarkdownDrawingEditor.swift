import PaperKit
import PencilKit
import PhotosUI
import SwiftUI
import UIKit

enum CanvasPaperStyle: String, CaseIterable, Codable, Identifiable, Sendable {
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

struct CanvasPaperDocument: Sendable {
    private struct Envelope: Codable {
        let format: String
        let version: Int
        let paperStyle: CanvasPaperStyle
        let markupData: Data
        let linkCards: [CanvasLinkCard]?
    }

    private static let format = "io.github.saxonbobart.lists.paper-markup"
    private static let defaultBounds = CGRect(x: 0, y: 0, width: 1_024, height: 1_365)

    var markup: PaperMarkup
    var paperStyle: CanvasPaperStyle
    var linkCards: [CanvasLinkCard]

    var hasContent: Bool {
        let frame = markup.contentsRenderFrame
        return frame.isEmpty == false && frame.isNull == false && frame.isInfinite == false
    }

    static func blank(paperStyle: CanvasPaperStyle = .plain) -> Self {
        var markup = PaperMarkup(bounds: defaultBounds)
        makeBackgroundTransparent(&markup)
        return Self(markup: markup, paperStyle: paperStyle, linkCards: [])
    }

    init(
        markup: PaperMarkup,
        paperStyle: CanvasPaperStyle,
        linkCards: [CanvasLinkCard] = []
    ) {
        var markup = markup
        Self.makeBackgroundTransparent(&markup)
        self.markup = markup
        self.paperStyle = paperStyle
        self.linkCards = linkCards
    }

    init(dataRepresentation data: Data) throws {
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           envelope.format == Self.format,
           (1...2).contains(envelope.version) {
            self.init(
                markup: try PaperMarkup(dataRepresentation: envelope.markupData),
                paperStyle: envelope.paperStyle,
                linkCards: envelope.linkCards ?? []
            )
            return
        }

        // PaperKit's own serialized data is accepted so exported sidecars can
        // still be reopened if they are separated from the Lists envelope.
        if let markup = try? PaperMarkup(dataRepresentation: data) {
            self.init(markup: markup, paperStyle: .plain)
            return
        }

        // Raw PencilKit data is also accepted so native stroke files can be
        // opened as editable PaperKit content instead of being flattened.
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
            version: 2,
            paperStyle: paperStyle,
            markupData: markupData,
            linkCards: linkCards
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
        let traits = UITraitCollection(userInterfaceStyle: darkMode ? .dark : .light)
        for card in linkCards {
            let cardRect = CGRect(
                x: (card.x - card.width / 2 - paperBounds.minX) * renderFrame.width / paperBounds.width,
                y: (card.y - card.height / 2 - paperBounds.minY) * renderFrame.height / paperBounds.height,
                width: card.width * renderFrame.width / paperBounds.width,
                height: card.height * renderFrame.height / paperBounds.height
            )
            guard let cardImage = Self.linkCardImage(
                title: card.title,
                destination: card.destination,
                size: cardRect.size,
                traits: traits
            ).cgImage else { continue }
            // PaperKit renders into a Quartz y-up context. Convert the card's
            // top-origin canvas position to that coordinate space; CGImage
            // drawing then preserves the UIKit-authored image orientation.
            context.draw(cardImage, in: CGRect(
                x: cardRect.minX,
                y: renderFrame.height - cardRect.maxY,
                width: cardRect.width,
                height: cardRect.height
            ))
        }
        guard let image = context.makeImage() else {
            throw AttachmentStorageError.emptyData
        }
        return UIImage(cgImage: image)
    }

    @MainActor
    static func linkCardImage(
        title: String,
        destination: String,
        size: CGSize,
        traits: UITraitCollection
    ) -> UIImage {
        var renderedImage: UIImage?
        traits.performAsCurrent {
            let format = UIGraphicsImageRendererFormat.preferred()
            format.scale = max(2, traits.displayScale)
            renderedImage = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let rect = CGRect(origin: .zero, size: size)
                let path = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 16)
                UIColor.secondarySystemBackground.setFill()
                path.fill()
                UIColor.separator.withAlphaComponent(0.6).setStroke()
                path.lineWidth = 1
                path.stroke()

                let symbolSize: CGFloat = 26
                let symbolRect = CGRect(
                    x: 20,
                    y: (size.height - symbolSize) / 2,
                    width: symbolSize,
                    height: symbolSize
                )
                let symbol = UIImage(
                    systemName: "link",
                    withConfiguration: UIImage.SymbolConfiguration(
                        pointSize: 21,
                        weight: .semibold
                    )
                )?.withTintColor(.tintColor, renderingMode: .alwaysOriginal)
                symbol?.draw(in: symbolRect)

                let textX = symbolRect.maxX + 14
                let textWidth = max(1, size.width - textX - 18)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                NSAttributedString(
                    string: title,
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .headline),
                        .foregroundColor: UIColor.label,
                        .paragraphStyle: paragraph,
                    ]
                ).draw(in: CGRect(x: textX, y: 18, width: textWidth, height: 26))
                NSAttributedString(
                    string: linkSubtitle(destination),
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .caption1),
                        .foregroundColor: UIColor.secondaryLabel,
                        .paragraphStyle: paragraph,
                    ]
                ).draw(in: CGRect(x: textX, y: 49, width: textWidth, height: 20))
            }
        }
        return renderedImage ?? UIImage()
    }

    private static func linkSubtitle(_ destination: String) -> String {
        guard let url = URL(string: destination), let host = url.host else {
            return destination.removingPercentEncoding ?? destination
        }
        return host
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

struct CanvasLinkInsertion: Equatable, Sendable {
    let id: UUID
    let title: String
    let destination: String

    init(id: UUID = UUID(), title: String, destination: String) {
        self.id = id
        self.title = title
        self.destination = destination
    }
}

struct PaperCanvasEditor: View {
    let isEditing: Bool
    let navigationTitle: String
    let allowsEmptyDocument: Bool
    let editableTitle: Binding<String>?
    let linkToInsert: Binding<CanvasLinkInsertion?>?
    let onRequestLink: (() -> Void)?
    let onOpenLink: ((String) -> Void)?
    let suspendsToolPicker: Bool
    let accessibilityPrefix: String
    let onComplete: (CanvasPaperDocument?) -> Void
    @State private var document: CanvasPaperDocument
    @State private var presentObjectsToken = UUID()
    @State private var selectedImage: PhotosPickerItem?
    @State private var imageImportFailure: String?
    @State private var viewportState = CanvasViewportState()
    @State private var showsToolPicker = true

    init(
        document: CanvasPaperDocument = .blank(),
        isEditing: Bool = false,
        navigationTitle: String = "Drawing",
        allowsEmptyDocument: Bool = false,
        editableTitle: Binding<String>? = nil,
        linkToInsert: Binding<CanvasLinkInsertion?>? = nil,
        onRequestLink: (() -> Void)? = nil,
        onOpenLink: ((String) -> Void)? = nil,
        suspendsToolPicker: Bool = false,
        accessibilityPrefix: String = "document.drawing",
        onComplete: @escaping (CanvasPaperDocument?) -> Void
    ) {
        self.isEditing = isEditing
        self.navigationTitle = navigationTitle
        self.allowsEmptyDocument = allowsEmptyDocument
        self.editableTitle = editableTitle
        self.linkToInsert = linkToInsert
        self.onRequestLink = onRequestLink
        self.onOpenLink = onOpenLink
        self.suspendsToolPicker = suspendsToolPicker
        self.accessibilityPrefix = accessibilityPrefix
        self.onComplete = onComplete
        _document = State(initialValue: document)
    }

    var body: some View {
        NavigationStack {
            PaperCanvas(
                document: $document,
                presentObjectsToken: presentObjectsToken,
                onOpenLink: onOpenLink,
                suspendsToolPicker: suspendsToolPicker,
                showsToolPicker: showsToolPicker,
                viewportState: viewportState
            )
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { onComplete(nil) }
                            .accessibilityIdentifier("\(accessibilityPrefix).cancel")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if editableTitle == nil {
                            paperMenu
                            addObjectButton
                        } else {
                            canvasToolsMenu
                        }

                        Button(isEditing ? "Save" : "Add") { onComplete(document) }
                            .fontWeight(.semibold)
                            .disabled(allowsEmptyDocument == false && document.hasContent == false)
                            .accessibilityIdentifier("\(accessibilityPrefix).\(isEditing ? "save" : "add")")
                    }
                    if let editableTitle {
                        ToolbarItem(placement: .principal) {
                            TextField("Untitled Canvas", text: editableTitle)
                                .multilineTextAlignment(.center)
                                .font(.headline)
                                .accessibilityIdentifier("\(accessibilityPrefix).title")
                        }
                    }
                }
        }
        .accessibilityIdentifier("\(accessibilityPrefix).editor")
        .onChange(of: selectedImage) { _, item in
            guard let item else { return }
            Task { await insertImage(from: item) }
        }
        .onChange(of: linkToInsert?.wrappedValue) { _, insertion in
            guard let insertion else { return }
            insertLink(insertion)
        }
        .alert(
            "Couldn’t Add Image",
            isPresented: Binding(
                get: { imageImportFailure != nil },
                set: { if $0 == false { imageImportFailure = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("\(accessibilityPrefix).image.error.dismiss")
        } message: {
            Text(imageImportFailure ?? "The image could not be added to this canvas.")
        }
    }

    private var paperMenu: some View {
        Menu("Paper", systemImage: document.paperStyle.systemImage) {
            ForEach(CanvasPaperStyle.allCases) { style in
                Button {
                    document.paperStyle = style
                } label: {
                    Label(style.title, systemImage: style.systemImage)
                }
            }
        }
        .accessibilityIdentifier("\(accessibilityPrefix).paper")
    }

    private var addObjectButton: some View {
        Button("Add Object", systemImage: "square.on.circle") {
            presentObjectsToken = UUID()
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("\(accessibilityPrefix).objects")
    }

    /// First-class canvases keep a useful editable title in the compact iPhone
    /// navigation bar by grouping secondary authoring controls into one menu.
    private var canvasToolsMenu: some View {
        Menu("Canvas Tools", systemImage: "ellipsis.circle") {
            Toggle(isOn: $showsToolPicker) {
                Label("Drawing Tools", systemImage: "pencil.tip")
            }
            .accessibilityIdentifier("\(accessibilityPrefix).drawingtools")
            Section("Paper") {
                ForEach(CanvasPaperStyle.allCases) { style in
                    Button {
                        document.paperStyle = style
                    } label: {
                        Label(style.title, systemImage: style.systemImage)
                    }
                }
            }
            Button("Add Object", systemImage: "square.on.circle") {
                presentObjectsToken = UUID()
            }
            PhotosPicker(selection: $selectedImage, matching: .images) {
                Label("Add Image", systemImage: "photo")
            }
            .accessibilityIdentifier("\(accessibilityPrefix).image")
            if let onRequestLink {
                Button("Add Link", systemImage: "link") {
                    onRequestLink()
                }
                .accessibilityIdentifier("\(accessibilityPrefix).link")
            }
            if document.linkCards.isEmpty == false {
                Menu("Links", systemImage: "link.circle") {
                    ForEach(document.linkCards) { card in
                        Menu(card.title) {
                            if let onOpenLink {
                                Button("Open", systemImage: "arrow.up.right") {
                                    onOpenLink(card.destination)
                                }
                            }
                            Button("Remove from Canvas", systemImage: "trash", role: .destructive) {
                                document.linkCards.removeAll { $0.id == card.id }
                            }
                        }
                        .accessibilityIdentifier("\(accessibilityPrefix).link.\(card.id.uuidString)")
                    }
                }
            }
        }
        .accessibilityIdentifier("\(accessibilityPrefix).tools")
    }

    @MainActor
    private func insertImage(from item: PhotosPickerItem) async {
        defer { selectedImage = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let cgImage = image.cgImage else {
                throw AttachmentStorageError.emptyData
            }
            let bounds = document.markup.bounds
            let available = CGSize(
                width: max(240, bounds.width * 0.62),
                height: max(240, bounds.height * 0.62)
            )
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            let scale = min(
                1,
                min(
                    available.width / max(1, imageSize.width),
                    available.height / max(1, imageSize.height)
                )
            )
            let size = CGSize(
                width: max(120, imageSize.width * scale),
                height: max(120, imageSize.height * scale)
            )
            let frame = CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            document.markup.insertNewImage(cgImage, frame: frame)
        } catch {
            imageImportFailure = error.localizedDescription
        }
    }

    private func insertLink(_ insertion: CanvasLinkInsertion) {
        let bounds = document.markup.bounds
        let visibleFrame = viewportState.visibleFrame
        let insertionFrame = visibleFrame.isEmpty || visibleFrame.isNull || visibleFrame.isInfinite
            ? bounds
            : visibleFrame
        let width = min(max(280, insertionFrame.width * 0.78), 520)
        document.linkCards.append(CanvasLinkCard(
            title: insertion.title,
            destination: insertion.destination,
            x: insertionFrame.midX,
            y: insertionFrame.midY,
            width: width,
            height: 88
        ))
    }
}

@MainActor
private final class CanvasViewportState {
    var visibleFrame: CGRect = .zero
}

private struct PaperCanvas: UIViewControllerRepresentable {
    @Binding var document: CanvasPaperDocument
    let presentObjectsToken: UUID
    let onOpenLink: ((String) -> Void)?
    let suspendsToolPicker: Bool
    let showsToolPicker: Bool
    let viewportState: CanvasViewportState

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
        context.coordinator.syncLinkAdornments(on: controller)
        DispatchQueue.main.async {
            context.coordinator.updateViewportState()
            context.coordinator.restoreToolPickerIfNeeded()
        }
        return controller
    }

    func updateUIViewController(_ controller: PaperMarkupViewController, context: Context) {
        context.coordinator.parent = self
        viewportState.visibleFrame = controller.contentVisibleFrame
        if controller.markup != document.markup {
            controller.markup = document.markup
        }
        context.coordinator.updateBackground(style: document.paperStyle, on: controller)
        context.coordinator.syncLinkAdornments(on: controller)
        if suspendsToolPicker || showsToolPicker == false {
            context.coordinator.suspendToolPicker()
        } else {
            context.coordinator.activateToolPicker()
        }
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
        private var lastAdornmentSignature: AdornmentSignature?

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
            controller.becomeFirstResponder()
            toolPicker.setVisible(true, forFirstResponder: controller)
        }

        func suspendToolPicker() {
            guard let controller, isToolPickerAttached else { return }
            toolPicker.setVisible(false, forFirstResponder: controller)
            controller.pencilKitResponderState.activeToolPicker = toolPicker
            controller.pencilKitResponderState.toolPickerVisibility = .inactive
            toolPicker.removeObserver(controller)
            isToolPickerAttached = false
            controller.resignFirstResponder()
        }

        func restoreToolPickerIfNeeded() {
            guard parent.showsToolPicker, parent.suspendsToolPicker == false else {
                suspendToolPicker()
                return
            }
            activateToolPicker()
        }

        func updateBackground(style: CanvasPaperStyle, on controller: PaperMarkupViewController) {
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

        func updateViewportState() {
            guard let controller else { return }
            parent.viewportState.visibleFrame = controller.contentVisibleFrame
        }

        func syncLinkAdornments(on controller: PaperMarkupViewController) {
            guard #available(iOS 27.0, *) else { return }
            let traits = controller.traitCollection
            let signature = AdornmentSignature(
                cards: parent.document.linkCards,
                interfaceStyle: traits.userInterfaceStyle,
                contentSizeCategory: traits.preferredContentSizeCategory,
                displayScale: traits.displayScale
            )
            guard signature != lastAdornmentSignature else { return }
            // Cache before assigning. PaperKit invalidates the representable
            // synchronously when its adornments change, so assigning first
            // would recursively rebuild the same adornments forever.
            lastAdornmentSignature = signature
            controller.adornments = signature.cards.map { card in
                let size = CGSize(width: card.width, height: card.height)
                return MarkupAdornment(
                    id: card.id,
                    anchor: .canvas(location: CGPoint(x: card.x, y: card.y)),
                    imageConfiguration: .image(Self.linkCardImage(
                        title: card.title,
                        destination: card.destination,
                        size: size,
                        traits: traits
                    )),
                    dragRegion: .canvas,
                    scalesWithZoom: true
                )
            }
        }

        private struct AdornmentSignature: Equatable {
            let cards: [CanvasLinkCard]
            let interfaceStyle: UIUserInterfaceStyle
            let contentSizeCategory: UIContentSizeCategory
            let displayScale: CGFloat
        }

        private static func linkCardImage(
            title: String,
            destination: String,
            size: CGSize,
            traits: UITraitCollection
        ) -> UIImage {
            CanvasPaperDocument.linkCardImage(
                title: title,
                destination: destination,
                size: size,
                traits: traits
            )
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
            restoreToolPickerIfNeeded()
        }

        private func finishObjectInsertion(_ picker: MarkupEditViewController) {
            picker.dismiss(animated: true) { [weak self] in
                self?.restoreToolPickerIfNeeded()
            }
        }

        func paperMarkupViewControllerDidChangeMarkup(_ paperMarkupViewController: PaperMarkupViewController) {
            guard let markup = paperMarkupViewController.markup else { return }
            parent.document.markup = markup
        }

        func paperMarkupViewControllerDidChangeSelection(_: PaperMarkupViewController) {}
        func paperMarkupViewControllerDidBeginDrawing(_: PaperMarkupViewController) {}
        func paperMarkupViewControllerDidChangeContentVisibleFrame(_: PaperMarkupViewController) {
            updateViewportState()
        }

        @available(iOS 27.0, *)
        func paperMarkupViewController(
            _: PaperMarkupViewController,
            didTapAdornmentWithID id: UUID
        ) {
            guard let destination = parent.document.linkCards.first(where: { $0.id == id })?.destination
            else { return }
            parent.onOpenLink?(destination)
        }

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
            _ controller: PaperMarkupViewController,
            didUpdateAdornmentWithID id: UUID,
            toAnchor anchor: MarkupAdornment.Anchor
        ) {
            guard let markup = controller.markup,
                  let location = anchor.location(in: markup),
                  let index = parent.document.linkCards.firstIndex(where: { $0.id == id }) else {
                return
            }
            parent.document.linkCards[index].x = location.x
            parent.document.linkCards[index].y = location.y
        }
    }
}

private final class DrawingPaperBackgroundView: UIView {
    var style: CanvasPaperStyle

    init(style: CanvasPaperStyle) {
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
