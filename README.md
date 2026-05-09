# Lists

A calm, local-first markdown app for tasks, habits, and notes. Your data lives in plain markdown files with YAML frontmatter on disk — yours forever, in any text editor, on any device. iOS first; Android, Linux, and Windows planned.

Free and open source under **AGPL-3.0-or-later**.

> **Status:** Pre-v1, in active development.

## Run on iOS simulator

Requires Xcode 26+, Swift 6.2, iOS 26+ simulator, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd platforms/ios
xcodegen generate
open Lists.xcodeproj
# ⌘R to run on iPhone 17 Pro
```

## Documentation

| File | Purpose |
|---|---|
| [`PRODUCT-SPEC.md`](PRODUCT-SPEC.md) | Full product specification (the source of truth for behavior) |
| [`CLAUDE.md`](CLAUDE.md) | How to work in this repo with Claude Code |
| [`docs/CURRENT.md`](docs/CURRENT.md) | Current milestone + recent decisions |
| [`research/PLAN.md`](research/PLAN.md) | Multi-platform plan (build order, per-platform stack picks) |
| [`shared/`](shared/) | Language-neutral file format spec, fixtures, lexicons |
| [`design/`](design/) | Design handoff bundle — open `Claude Design/project/Lists Design.html` in a browser |

## License

[AGPL-3.0-or-later](LICENSE). Both the client app and the (future) sync server are AGPL.
