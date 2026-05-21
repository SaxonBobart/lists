---
description: Write or fix a gesture test using the gesture-test-author subagent.
argument-hint: "<feature or test name>"
---

Dispatch the `gesture-test-author` subagent with the user's request as context. The subagent owns the test patterns and accessibility-id discipline. Don't write the test yourself — delegate.

Pass: $ARGUMENTS as the feature description, plus the current branch and any relevant SwiftUI view paths if known.
