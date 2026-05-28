# Skill: flutter-layout
## When to use
Triggered when the task involves:
- Any UI widget that responds to width or screen size
- Layout files (`app_layout.dart`, scaffolds, sidebars, page shells)
- Responsive breakpoint logic
- The goal ladder, chart cards, or any visual contract surface
- Adding a new screen or major view
## The invariants
### F1. LayoutBuilder, never MediaQuery for width-responsive UI
`MediaQuery.of(context).size.width` reflects the *window*, not the *widget's available space*. In a desktop-first layout with a persistent sidebar, MediaQuery lies — the widget has less width than the window.
- Use `LayoutBuilder` and switch on `constraints.maxWidth`.
- MediaQuery is acceptable only for: device pixel ratio, text scale factor, system padding.
- If you see `MediaQuery.of(context).size` in a layout decision, it's a bug.
### F2. Desktop-first via app_layout.dart with persistent sidebar
Cue is a clinician tool. The primary form factor is desktop browser with a persistent sidebar.
- All major screens render inside `app_layout.dart`'s shell.
- Mobile-web is a degraded but functional secondary, not the design target.
- The sidebar is persistent (not a drawer) above the medium breakpoint.
### F3. Sub-1s utterance-to-action budget governs interaction design
See `product-law` P4. In layout terms:
- No layout shift on data arrival — reserve space with skeletons or fixed heights.
- No spinners longer than 200ms for actions the SLP triggered; use optimistic UI.
- ⌘K recall sandbox baseline is 98–300ms; do not regress this.
### F4. Visual contracts are golden-tested
Some UI surfaces have explicit visual contracts that must not drift:
- **Goal ladder cards:** DM Sans 18/w700 for identifier rank; olive ring focus animation; hover-lift; focused-card deepened surface.
- **Chart goal ladder:** the spacing, identifier rank, and focused-state surface depth.
- **Today view:** the structured info hierarchy.
Changes to these surfaces require updating golden tests, not just the widget.
### F5. State management is explicit
- Riverpod (or your chosen state library) usage is consistent across the codebase.
- No `StatefulWidget` hidden state for anything that another widget reads.
- Auth-null guard is mandatory: any widget that reads `user` must handle the null case explicitly, not crash.
## Anti-rationalizations
| Excuse                                                | Counter |
|-------------------------------------------------------|---------|
| "MediaQuery is shorter, just one line"                | Wrong abstraction. Every "just one line" MediaQuery becomes a layout bug when the sidebar opens. Use LayoutBuilder. |
| "It looks fine on my screen"                          | Cue runs on clinician laptops, tablets, and shared clinic monitors. Test at 1024px, 1280px, 1440px minimum. |
| "Skeleton loaders are overkill for this view"         | Layout shift breaks the sub-1s perceived budget even when the data is fast. Reserve space. |
| "The visual contract is implicit, designers will catch it" | There is no designer. You are the visual contract. Golden test or it drifts. |
| "I'll add the auth-null guard later"                  | "Later" is when a clinician sees a crash mid-session. Guard now. |
## Evidence of compliance
Before considering a layout change complete, produce:
- Search the changed files for `MediaQuery.of(context).size` — must return zero matches in width-responsive logic.
- Visual check at 1024 / 1280 / 1440 px widths.
- For golden-tested surfaces: updated goldens with diff reviewed.
- For new widgets that read auth/user: explicit null-handling path tested.
- For data-loading widgets: no layout shift on data arrival (skeleton or fixed-height reservation).
