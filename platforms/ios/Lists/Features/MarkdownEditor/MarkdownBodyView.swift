import MarkdownUI
import SwiftUI

/// Read-only GFM renderer for full note bodies. The editor keeps its
/// custom live-typing renderer; read surfaces use MarkdownUI's
/// cmark-gfm-backed parser for spec-level block rendering.
struct MarkdownBodyView: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        Markdown(source)
            .markdownTheme(.gitHub)
            .fixedSize(horizontal: false, vertical: true)
    }
}
