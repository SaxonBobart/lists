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
            // Privacy: never fetch remote images from note bodies. The `.asset`
            // providers resolve bundle assets only (no URLSession), so a remote
            // `![](http…)` renders as nothing instead of pinging a third-party
            // server and leaking the user's IP — keeping the "no cloud" promise.
            // Both block (.markdownImageProvider) and inline (![]() in a
            // paragraph) paths must be pinned; omitting the inline one leaves the
            // leak half-open.
            .markdownImageProvider(.asset)
            .markdownInlineImageProvider(.asset)
            .fixedSize(horizontal: false, vertical: true)
    }
}
