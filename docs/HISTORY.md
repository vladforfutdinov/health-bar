# History

## 2026-11-09 — initial design

- AppKit `NSStatusItem` over SwiftUI `MenuBarExtra`: `MenuBarExtra` forces a template (monochrome) label; the icon must be coloured.
- Icon colour follows the official `status.indicator`, not component statuses: Supabase has ~189 region components and one degraded region would keep the icon orange.
- incident.io pages (OpenAI, Supabase): their Statuspage-compatible `summary.json` returned 1 of 189 components for Supabase and no groups for OpenAI, so groups/components come from the page's own `/proxy/<host>` feed, with fallback to `summary.json`. Incidents come from `summary.json` because its update text is plain, while the proxy's is a rich-text tree.
- Platform detection: `/proxy/<host>` returns 404 on Statuspage hosts (checked on githubstatus, status.claude.com, vercel-status), which is cached as "Statuspage".
- Release pipeline (Developer ID, notarytool, Sparkle on gh-pages, Homebrew tap) ported from reLayout, macOS only.

## 2026-11-09 — menu glyphs moved into item titles

On macOS 27.2 `NSMenuItem.image` is not drawn in the status menu at all: a drawingHandler image, a plain bitmap and an SF Symbol all stayed invisible while the state checkmark column rendered (repro: scratch app popping an `NSMenu` and screen-capturing it). No user default controlling it was found. The glyph is now an `NSTextAttachment` at the start of `attributedTitle`, which renders. No unit-test seam: the symptom is AppKit menu drawing.

## 2026-11-09 — stable status item identity

Thaw (Ice fork) keyed the item as `<bundle id>:HealthBar: ok`, i.e. by its accessibility label, which included the current state. Every state change looked like a new item, and new items land in Thaw's hidden section, so the item vanished even after being moved to the visible section. The label is now the constant `HealthBar` (state goes to the accessibility value and tooltip), matching reLayout.

Follow-up, 2026-11-10 (Thaw 3.0.0-beta.6 source, thaw-app/Thaw):
- In Thaw's **standard** hiding mode macOS 27 hides items per app (`hiddenWins`, `AppSiblingSections.swift`): one item of an app in Hidden conceals all of them. Native mode is `visibleWins`.
- macOS keys an item's position as `status:<owner>::<autosaveName>`, the owner being the bundle id or the registered process name. Every build so far ran as process `HealthBar` with `autosaveName` `HealthBar`, so dev, release and test builds shared keys; Thaw "mirrors sibling keys" across them, and a stale `…healthbar.dev::HealthBar: ok` key (from the state-carrying label) kept attracting writes for the dev bundle id. Items landed on the same x, got a "phantom frame", were marked stranded and stayed parked.
- Changes: `autosaveName` = bundle id; dev builds use bundle id `….debug` and executable `HealthBarDev`.
- Result: the release build alone in Visible stays put in standard mode. With a dev and a release copy running together, Thaw still interpolates both into the same position slot (`Interpolated … to 1145 between 1143 and 1147`) and one of them goes phantom; quit one copy (or use native mode) while testing. Stale state is cleared with Thaw quit: `defaults delete com.stonerl.Thaw StrandedMenuBarItems`.

## 2026-11-10 — pie menu bar icon

The bar icon was one glyph for the worst status (filled / half / ring). It is now a pie with one sector per service in config order, each coloured by that service's `status.indicator`, so the icon shows which service is affected. Maintenance (blue) and unreachable (grey) now show in the icon too. Menu rows keep the per-status glyphs.

Drawn as a donut with the hole at 60% of the radius, picked over a full pie and a 45% hole from side-by-side renders at 16 pt on dark and light bars.

## 2026-11-10 — uptime strips replace the components submenu

The second menu level (groups and components) is gone; each service gets a 30-day uptime strip and percentage instead, and its submenu keeps only active incidents.
- Neither platform publishes page-level history, so the strip is built from components: each day is the worst component that day, the percentage is the least available component (the mean hid single-component outages on pages with 59–189 components).
- Polling split by cost (measured, gzip): `status.json` ~0.2 KB per service every minute; summary + history 4–58 KB per service, read at launch, on a status change, then hourly, or every 15 min while not operational. The old per-minute `summary.json` + `/proxy` cost ~19 KB per poll, ~28 MB/day.
- `incidents.json` was rejected as a history source: incident.io returns the last 25 incidents (26 days for OpenAI), and it carries no percentage.
- incident.io's percentage is computed with Statuspage's formula (major outage in full, partial 30%, degraded performance 0) so the two platforms read alike; incident.io's own `component_uptimes` is 90-day only.

## 2026-11-10 — menu updates while open

- Service rows lost their submenu (it held only "Open Status Page" and incidents); the row opens the page, incidents go to the tooltip, and an external-link mark sits where the chevron was.
- A menu opened during loading never showed the results. Two causes: each render assigned a new `NSMenu` to the status item (the open one is now refilled in place), and while a menu is tracked the run loop stays in `NSEventTrackingRunLoopMode`, where common-mode timers fire but the main dispatch queue is not drained, so neither `DispatchQueue.main` blocks nor `@MainActor` continuations ran until it closed (repro: `popUp` the menu, log from a main-queue block and from a common-mode timer). Poll results now come back via `RunLoop.main.perform(inModes: [.common])`.
- The link mark and the shortcuts are drawn as right-aligned tab-stop text: macOS reserves a key-equivalent column (~50 pt) on every row once any item shows one, which left a blank band right of the link marks. ⌘R and ⌘Q are owned by hidden twin items (`allowsKeyEquivalentWhenHidden`), which reserve no column.
- Each service is one two-line item (status, then strip), so the selection highlight covers the whole block; the strip sits on a panel of `windowBackgroundColor` so its gaps and frame don't turn blue under the highlight.
- Services are polled independently and each renders when its own result arrives, instead of after the slowest one.

## 2026-11-10 — per-day strip tooltips

- The strip stretches to fill the row: bars widen so the strip ends before the widest percentage (`100.00 %`), which is right-aligned under the link mark.
- Hovering a strip bar shows that day: each affected component (`Group · Component`) with its status and time in it, most severe first, capped at 8 lines.
- A menu item has one tooltip, so a service is now an `NSMenuItem.view` (`ServiceRowView`) with one `addToolTip` rect per bar. The view draws its own selection and text colours and sends the item's action on mouse-up.
- Durations: Statuspage's `uptime_showcase` gives seconds of partial (`p`) and major (`m`) outage per component per day. incident.io's `component_impacts` gives start/end per component, split at local midnight.
- Names: Statuspage from `summary.json` (`group_id`), already fetched. incident.io from `/proxy/<host>` (`summary.structure`, 4–8 KB gzip), read with the strip; if it fails, ids are shown.
- Checked in the `mac-vm` guest (macOS 26.6): per-bar tooltips change bar to bar, the row tooltip stays over the status line, a click opens the page, and the per-minute refill keeps the open menu (the replaced view drops its tooltip). A copy on the dev Mac closed its menu while the pointer was moved by script during the user's own work; not reproduced in the guest.

## 2026-11-10 — light-theme status colours, Quit action

- The standard system colours read pale on light menus and menu bars. Status colours are now dynamic: system colours on dark appearances, own sRGB shades on light ones (green 40,172,72; orange 245,128,0; red 228,28,38; blue 0,104,240; grey 188,188,193). A first set close to Apple's increased-contrast values (green 36,138,61, grey 108,108,112) was too dark: in the bar icon grey and green sectors merged while it filled in. Healthy strip bars were first dimmed (45% opacity on dark, 70% on light); they are now drawn opaque so the strip, the menu glyphs and the bar icon share one set of colours. Resolving system colours under `accessibilityHighContrastAqua` returned the standard values, so the shades are explicit.
- Tuned by eye: grey 15% lighter on light (198,198,202) and darker on dark (110,110,113, systemGray × 0.85²); green 15% brighter on light (46,198,83) and 15% darker on dark (41,178,75, from systemGreen).
- macOS 26 adds a stock icon to items whose action is `NSApplication.terminate(_:)`, indenting Quit; the item calls its own `quit` action instead.

## 2026-11-10 — refresh starts from no data

Refresh (menu, wake, launch, config reload) clears every service to "updating…" and the icon to grey before polling, so what is shown after it is only what that refresh read; services fill in as they answer.
- The Refresh item is a `RowView` that leaves the menu open, so the refill can be watched.
- A service without data shows an empty grey strip, so rows keep their height; while services load the menu's right edge doesn't move in for the shorter "updating…" titles.

## 2026-11-10 — build targets the declared minimum macOS

`swiftc` ran without `-target`, so the binary's `minos` was the build machine's macOS (27.2 locally, the `macos-latest` runner's in CI) while `Info.plist` declared 13.0: v0.1.0 and v0.2.0 do not launch on older systems. `build.sh` now passes `-target <arch>-apple-macos<LSMinimumSystemVersion>`. Found when a local build would not run in the macOS 26 test VM.
