# Design

[iOS design rules](ios-design-rules.md) record the current native layout and
interaction contracts. Read them before changing visible UI, alongside the
relevant behavior in [PRODUCT-SPEC.md](../PRODUCT-SPEC.md).

Use a fresh simulator/device capture or focused hosted snapshot before UI work.
The retired full-screen reference set showed an older product and has been
removed. [Screen references](screens/README.md) includes one dated current Home
capture and explains the sources for other visual evidence.

The app uses SF Pro / SF Mono and the accent token in `Design/Tokens.swift`.
Design prototypes can communicate intent; the implemented native behavior is
the reference for further work.
