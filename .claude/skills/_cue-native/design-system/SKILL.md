# Skill: design-system
## When to use
Triggered when the task involves:
- Typography choices, font weight, font size
- Color decisions, focus states, hover states
- Component styling (buttons, cards, chips, inputs)
- The goal ladder visual language
- Logo, brand mark, brand specimens
- Any "make it look nicer" request
## The invariants
### D1. Typography stack
Three families, three roles, no substitutions:
- **Playfair Display** — hero/display/surgical. Serif. Used for major numbers, single-word emphasis, brand moments.
- **Syne** — labels, stats, buttons. Geometric/structured. Used where the SLP scans quickly.
- **DM Sans** — body, paragraph text, default UI. Used everywhere else.
The goal ladder's identifier rank is **DM Sans 18 / weight 700.** This is a fixed spec, not a suggestion.
### D2. Color tokens, not hex literals
- Colors live in a theme/tokens file, referenced by semantic name (`surface.focused`, `border.olive.focus`).
- No raw hex codes in widget files.
- The olive ring focus state is the focus signature for goal-ladder cards. Don't substitute with blue or system focus.
### D3. Focus and hover states are part of the contract
The goal ladder cards have:
- Olive ring animation on focus (not a static border).
- Hover-lift transform on the unfocused card.
- Deepened surface on the focused card (background goes one step darker, not lighter).
These are not optional polish — they encode the regulation-first hierarchy visually.
### D4. The logo is not locked — do not produce "final" marks
Three finalists currently under consideration:
- **Ictus** — single stroke
- **Measure** — four-beat conducting gesture
- **Ariadne's Thread**
Side-by-side specimens are the only valid format for logo decisions. Guru decides visually, never from description.
Forbidden: puzzle pieces, ribbons, triumph imagery, anything that contradicts neurodiversity-ethics framing. The brand does not perform "fixing autism."
### D5. The Apollo-Hospitals-style trust register
Cue's visual language sits in the clinical-trust register — closer to a hospital's signage than to a consumer app's marketing site. Implications:
- Restrained color palette.
- High typographic hierarchy (the type does the work, not graphics).
- Whitespace is structural, not decorative.
- No gradients-as-decoration, no glassmorphism, no playful illustrations in clinical surfaces.
### D6. Side-by-side for any visual decision
When proposing visual options to Guru, present them as side-by-side specimens, never as sequential descriptions. "Option A is heavier, Option B is lighter" is not actionable — both rendered, at the same scale, in the same context, is.
## Anti-rationalizations
| Excuse                                                  | Counter |
|---------------------------------------------------------|---------|
| "I'll use Google Fonts default for this one screen"     | Type system is identity. One default sans breaks it. Playfair / Syne / DM Sans only. |
| "Hex code is faster than looking up the token"          | Hex drift is how design systems die. Look up the token. |
| "System focus ring is fine for this input"              | System focus breaks the olive-ring signature. Use the tokenized focus state. |
| "I'll mock up a final logo for the demo"                | Logo is not locked. Mocks anchor expectations falsely. Use the wordmark only until decided. |
| "A subtle gradient would liven this up"                 | Cue is hospital-register, not consumer-marketing. No decorative gradients. |
| "Just describe the two options in text"                 | Visual decisions don't survive description. Render both. |
## Evidence of compliance
Before considering a visual change complete, produce:
- Confirmation typography matches the three-family stack with correct roles.
- Confirmation colors reference tokens, not hex literals.
- For new components: focus, hover, and disabled states explicitly defined.
- For logo/brand work: side-by-side specimens, no "final" claims.
- For clinical surfaces: visual review against the hospital-trust-register constraint.
