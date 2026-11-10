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
