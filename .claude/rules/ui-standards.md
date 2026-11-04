# UI Standards (adopted 2026-11-03)

Every UI change must meet these rules. Each rule has an ID: cite it in reviews
("violates UI-T1"). A rule marked **[check]** can be verified from the diff
alone. Others need the screenshot harness
(`ClaudeLifterUITests/ScreenshotHarness/`) or a simulator run.

These rules sit beside `swift-style.md`; where they conflict, this file wins
for anything a user can see. Platform baseline: Apple HIG for iOS 26 and later (Liquid
Glass); the phone runs iOS 27. Deployment target is iOS 17, so iOS 26-only APIs need
`if #available(iOS 26, *)` with a working iOS 17 fallback.

The user is one person: 45 minutes, 6 am, a busy commercial gym. He has the
phone in one hand, sweaty fingers, and glances at it between sets. He does
exercises out of order because equipment is taken, and skips the last one
when time runs out. Design for that. Nothing here is generic polish.

## 1. Tap targets

- **UI-T1 [check]** Every control's hit area is at least 44×44 pt. A `Button` or `Menu`
  whose label is an icon, or text styled `.caption`, `.caption2` or `.footnote`,
  must carry `.frame(minWidth: 44, minHeight: 44)` and
  `.contentShape(Rectangle())`, or use a bordered style at
  `.controlSize(.regular)` or larger. `.controlSize(.small)` and `.mini` are
  banned on any screen reachable during a workout.
- **UI-T2** Gym-critical controls are at least 56×56 pt: the set checkmark,
  rest timer ±/Skip, Finish, and "Machine taken". Gloves and sweat are the
  design case, not the edge case.
- **UI-T3** Leave about 12 pt around bezeled controls and about 24 pt around
  unbezeled ones, per the HIG Accessibility page. A divider counts as
  separation. No two targets may touch.
- **UI-T4 [check]** Never use `.onTapGesture` as an action on visible
  content. Use `Button`, which provides the highlight state, the button trait
  and VoiceOver activation. Exception: focus helpers that are
  `.accessibilityHidden(true)` over an already labelled control (see
  `FocusWithCaretAtEnd`).

## 2. Type

- **UI-Y1 [check]** Text uses Dynamic Type styles only. `.font(.system(size:))`
  is allowed only for decorative SF Symbols that are
  `.accessibilityHidden(true)`. Any other fixed size must use `@ScaledMetric`.
- **UI-Y2** Each role has one style:

  | Role | Style |
  |---|---|
  | Screen title | navigation bar (`.large` on tab roots, `.inline` when pushed) |
  | Card or exercise title | `.headline` |
  | Live numbers (weight, reps, timer) | `.title3` or larger, `.monospacedDigit()` |
  | Body text, notes | `.body` / `.callout` |
  | Supporting metadata | `.subheadline` / `.footnote` |
  | Column headers, timestamps | `.caption` |
  | `.caption2` | non-essential decoration only; never data, never a control label |

- **UI-Y3** Information needed between sets must be at least `.subheadline` and
  use `.primary` or `.secondary` foreground, never `.tertiary`. That
  information is the previous result, the target, the rest time remaining and
  the machine-settings note.
- **UI-Y4 [check]** Numbers that change or align in columns use `.monospacedDigit()`.

## 3. Spacing and shape

- **UI-S1 [check]** Spacing comes from the 4-pt grid: 4, 8, 12, 16, 20, 24 or 32.
  Screen edge margins use the system default (`.padding(.horizontal)`, 16 pt
  on iPhone).
- **UI-S2 [check]** Cards use a 12 pt corner radius with `style: .continuous`
  and 16 pt inner padding. Do not nest a card inside a card. Corner radii of
  8, 10 and 16 are not allowed on cards.
- **UI-S3** Related items are 4–8 pt apart, groups 16 pt, sections 24 pt.

## 4. Colour and appearance

- **UI-C1 [check]** Never force an appearance: no `.preferredColorScheme(...)`
  in production code, and no in-app appearance setting. The HIG says "Avoid
  offering an app-specific appearance setting." Every screen must work in
  light and dark mode. SPEC §10's "dark mode default" is met by following the
  system, which on Evan's phone is the setting he chooses.
- **UI-C2 [check]** Colours come from system semantic colours (`.primary`,
  `.secondary`, `Color(.systemBackground)`, `Color(.secondarySystemBackground)`,
  fills, separators) or from `BrandTheme` tokens defined in the asset catalogue
  with light and dark variants. Do not add new `Color(red:green:blue:)` values
  outside `BrandTheme`. Do not use raw `.orange`, `.green`, `.yellow` or `.red`
  for meaning. Use named semantic tokens such as `success`, `warning`,
  `destructive` and `accentText`.
- **UI-C3** Contrast is at least 4.5:1 for text under 18 pt (14 pt bold), at
  least 3:1 for larger text and for icons and control boundaries. Measured
  values today:
  - Brand terracotta `#D97757` on white is **3.1:1**. Use it for fills, icons
    and text at `.title3` bold or larger only.
  - Small accent text uses `accentText`: light `#A35941` (5.2:1), dark
    `#D97757` (5.5:1 on `#1C1C1E`).
  - System orange and green text on white is about 2.2:1. Do not use them as
    text colour.
- **UI-C4** Colour is never the only signal. A completed set uses a filled
  check and a tint. Drift uses an icon and an orange tint. The VoiceOver value
  says the same thing.
- **UI-C5** One meaning, one colour, across the app. "Completed" uses the same
  token in the workout, History and the summary (today it is terracotta in
  the workout and green in History).

## 5. Components

- **UI-P1 Cards.** Use one shared card container (UI-S2). The header is the
  title plus at most one trailing action. Only the screen's primary action
  gets a tinted background. The HIG Color page says to "refrain from adding
  color to the background of multiple controls", so secondary buttons are
  plain or gray `.bordered`. Today Home tints five buttons.
- **UI-P2 Home density.** Home content scrolls as one list. Nothing is pinned
  above a scrolling list. Above the fold, before any status card, comes
  **today's workout action**. A new Home card must replace or merge an
  existing one, or go behind a summary row, so Home has at most four cards
  plus the start action. Status cards with nothing to report (zero counts,
  no changes) do not render.
- **UI-P3 Set rows.** Columns are `SET | PREVIOUS | WEIGHT × REPS | ✓`.
  - Fields are pre-filled and committed, not ghost text, wherever the value
    is unambiguous.
  - The checkmark meets UI-T2.
  - A completed row shows a filled check, a tint and VoiceOver value
    "completed".
  - At accessibility sizes, the row stacks (already built, keep it).
- **UI-P4 Sheets.**
  - Every sheet has a visible Cancel/Close in the toolbar. Swipe-to-dismiss
    is never the only way out.
  - Quick-entry sheets (log weight, note, report) use `.presentationDetents`
    with `.medium` or a fitted height, and focus the first field.
  - Any sheet with a text field has a keyboard Done that dismisses.
  - Do not present a sheet from a sheet.
- **UI-P5 Disclosure rows.** A collapsed row shows a one-line summary and a
  chevron, and the whole row is the target (UI-T1). VoiceOver announces
  expanded or collapsed: use `DisclosureGroup`, or set `accessibilityValue`.
  Collapsed is the default for anything not needed every set.
- **UI-P6 Destructive actions.**
  - Use `role: .destructive`, rendered system red: never let the app tint
    recolour it.
  - In menus it goes last. In confirmation dialogs it goes first, with Cancel
    last (HIG Action Sheets).
  - Irreversible data loss needs a confirmation. Use `.alert` with a Cancel
    button: on iOS 27 at AX5 a `confirmationDialog` can fill the screen and
    show no Cancel (seen 2026-11-04).
  - **[check]** Destructive swipe actions set `allowsFullSwipe: false`.
  - A reversible action prefers undo (a toast or the same menu) over a
    confirmation.
- **UI-P7 Never swipe-only [check].** Every `.swipeActions` or `.contextMenu`
  action, and every long-press action, is also reachable from a visible
  control: a row menu (`ellipsis.circle`), the detail screen or a toolbar
  item. Pull-to-refresh also needs an automatic refresh (#154 is the
  precedent).
- **UI-P8 Menus.** A menu has at most seven items, grouped with `Section`,
  with destructive items last. A menu that hides the screen's main action is
  a bug.
- **UI-P9 Toolbars.** At most one prominent trailing action. During a
  workout, Finish is prominent (`.borderedProminent`, or `.glassProminent`
  on iOS 26) and lives where the thumb is. Use standard bar components and
  do not paint custom backgrounds behind Liquid Glass bars. Glass belongs to
  the control layer only (HIG Materials: "Don't use Liquid Glass in the
  content layer"). Cards and rows use solid semantic backgrounds.
- **UI-P10 Search and filters compose.** A search query and filter chips
  combine with AND. Changing one never clears the other (#155).

## 6. States

- **UI-E1** Every list or data screen implements four states: loading,
  empty, error and content.
  - Loading: a `ProgressView` with a label if it can exceed 300 ms.
  - Empty: `ContentUnavailableView` that names the next action.
  - Error: an inline banner with Retry. Use an alert only when the user must
    decide something.
- **UI-E2 [check]** No silent failure in view actions. A `try?` in a Button
  action or `.task` needs a visible fallback (banner, inline message, or a
  documented reason in a comment).
- **UI-E3** Nothing modal interrupts a set. During a workout, only data-loss
  confirmations may block. Errors are banners.
- **UI-E4** Status that can be stale (sync, weight entries, reports) shows
  its age ("2 days ago"), not just a value.
- **UI-E5** An untouched screen goes idle.
  - CPU near 0% after a second or two. If XCUITest logs "App event loop
    idle notification not received", or a query times out, treat it as a
    layout or invalidation loop, not a flaky test.
  - Don't compute sorted or filtered model arrays inside `body` for
    `ForEach`, `.onChange` or `.id`. Derive them in the ViewModel, or
    cache them.
  - Profile new list-heavy screens once with the Instruments SwiftUI
    template.

## 7. Haptics and motion

- **UI-H1 [check]** Use `.sensoryFeedback` (iOS 17+) on the view, not
  `UIFeedbackGenerator` in ViewModels.
- **UI-H2** These events must have haptics, and nothing else does:

  | Event | Feedback |
  |---|---|
  | Set completed | `.impact(weight: .medium)` |
  | Set un-completed | `.impact(weight: .light)` |
  | Rest finished | `.success`, plus a notification if backgrounded |
  | PR on summary | `.success` |
  | Exercise swapped | `.selection` |
  | Destructive action confirmed | `.warning` |

  No haptics on scroll, typing or chip selection.
- **UI-H3** Animations respect `accessibilityReduceMotion` (a crossfade or
  none). Rest timer progress may animate. Layout changes during a set may
  not, so the target never moves under the thumb.

## 8. Accessibility minimums

- **UI-A1 [check]** Every icon-only control has an `accessibilityLabel`, or uses
  `Label(title, systemImage:)` with `.labelStyle(.iconOnly)`. Identifiers
  (`accessibilityIdentifier`) are for tests and are not labels.
- **UI-A2** A composite row reads as one sentence, using
  `.accessibilityElement(children: .combine)` or an explicit label. Example:
  "Set 2. Previous 80 kilograms by 8. Weight 80, reps 8. Not completed."
- **UI-A3** Every new or changed screen is checked at
  `accessibility-extra-extra-extra-large`.
  - Nothing clips or truncates data.
  - Layouts switch to stacked via `dynamicTypeSize.isAccessibilitySize` or
    `ViewThatFits`.
  - No fixed `.frame(width:)` or `.frame(height:)` on containers that hold
    text.
- **UI-A4** Charts carry an `accessibilityLabel` summary (trend, latest
  value), or an `AXChartDescriptor`.
- **UI-A5** Calendar day cells, chips and custom controls expose the button
  trait and a full label ("Thursday 8 October, 1 workout, 12 sets").

## 9. Gym-context rules

- **UI-G1** Logging a planned set at the planned values takes one tap: the
  checkmark. No keyboard, no sheet, no confirmation.
- **UI-G2** Order is free. Any exercise is one tap or one short scroll away,
  and doing them out of order costs nothing. There is no "current exercise"
  lock, and there are no reorder prompts caused by it.
- **UI-G3** A busy machine is a first-class event. Swapping to a listed
  alternative takes at most 2 taps from the exercise card (#169) and never
  touches the template.
- **UI-G4** Decisions happen at the moment of change, not in an end-of-workout
  pile (#150). The finish screen confirms what happened and asks at most one
  question.
- **UI-G5** Thumb zone: frequent workout actions (Finish, rest controls, add
  or swap) sit in the bottom half of the screen. The top bar is for rare
  actions.
- **UI-G6** Minimal typing. Every workout-time input offers a non-typing path
  (stepper, chip, previous value, picker). Numbers use numeric keyboards.
  Free text is always optional.
- **UI-G7** Glanceable at arm's length: the timer is `.title2` or larger, live
  numbers `.title3` or larger, and the current exercise state is readable in
  under a second.
- **UI-G8** Interruptions are free. Backgrounding, a call, or a lock screen
  loses nothing. Returning lands on the same scroll position, and resuming
  takes one tap.

## 10. PR review checklist

Paste this into the PR description and tick each item. "n/a" needs a reason.

- [ ] Targets ≥44 pt; gym-critical ≥56 pt (UI-T1, UI-T2); no `.onTapGesture` actions (UI-T4)
- [ ] Dynamic Type styles only; between-set data ≥ `.subheadline`, not tertiary (UI-Y1, UI-Y3)
- [ ] Spacing on the 4-pt grid; cards radius 12 continuous (UI-S1, UI-S2)
- [ ] No forced colour scheme; semantic or `BrandTheme` colours only; contrast checked (UI-C1–C3)
- [ ] No swipe-only, long-press-only or pull-only actions (UI-P7); sheets have a visible close (UI-P4)
- [ ] Home density budget respected (UI-P2)
- [ ] Loading, empty and error states present; no silent `try?` (UI-E1, UI-E2)
- [ ] Changed screens go idle when untouched; no XCUITest idle or query timeouts (UI-E5)
- [ ] Haptics only for the UI-H2 events, via `.sensoryFeedback`
- [ ] Icon-only controls labelled; rows combined; checked at AX5 (UI-A1–A3)
- [ ] Tap count for any changed top task stated in the PR, before and after (UI-G1, UI-G3)
- [ ] Screenshots, light + dark, from the harness, attached for every changed screen
