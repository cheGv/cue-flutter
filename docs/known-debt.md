# Known Debt

Pre-existing issues identified but deliberately not fixed in the work that surfaced them. Each entry: location, what's wrong, why we're not fixing it now.

---

## MediaQuery use in `cue_reasoning_panel.dart`

- **Location:** [`lib/widgets/cue_reasoning_panel.dart:355`](../lib/widgets/cue_reasoning_panel.dart)
- **What:** `MediaQuery.of(context).size.width * 0.78` used to constrain message bubble width.
- **Violates:** `CLAUDE.md` — "Never use `MediaQuery` — always `LayoutBuilder`."
- **Found during:** 2026-05-13 framework-chip extraction scoping (task subsequently deferred).
- **Why not fix now:** the chip extraction itself was deferred. Touching the message bubble layout for an unrelated cleanup risks regressing the reasoning panel without test coverage on this surface. Fix it when the panel is next opened for substantive work, or pair with the deferred framework-chip extraction task.
